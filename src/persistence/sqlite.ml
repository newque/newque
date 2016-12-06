open Core.Std
open Lwt
(* Not opening Sqlite3, to make it more explicit and to wrap all calls to it *)
module S3 = Sqlite3
module Rc = Sqlite3.Rc
module Data = Sqlite3.Data

module Logger = Log.Make (struct let path = Log.outlog let section = "Sqlite" end)

type statements = {
  last_row: Sqlite3.stmt * string;
  count: Sqlite3.stmt * string;
  begin_transaction: Sqlite3.stmt * string;
  commit_transaction: Sqlite3.stmt * string;
  rollback_transaction: Sqlite3.stmt * string;
  truncate: Sqlite3.stmt * string;
  quick_check: Sqlite3.stmt * string;
}
type t = {
  db: Sqlite3.db sexp_opaque;
  file: string;
  avg_read: int;
  stmts: statements sexp_opaque;
} [@@deriving sexp]
(* Ridiculously high number of retries by default,
   because it is only retried when the db is locked.
   We only want it to fail in catastrophic cases. *)
let default_retries = 3
let insert_batch_size = 500

(******************
   LOW LEVEL FUNCTIONS
 ******************)
let clean_sync ~destroy stmt =
  match destroy with
  | true -> ignore (S3.finalize stmt)
  | false ->
    begin try
        (* S3.reset itself can throw *)
        begin match (S3.reset stmt) with
          | Rc.OK -> ()
          | _ -> failwith "Failed to reset statement"
        end
      with
      | ex ->
        async (fun () -> Logger.error (Exception.full ex));
        S3.recompile stmt
    end

let exec_sync db ?(retry=default_retries) ~destroy (stmt, sql) =
  async (fun () -> Logger.debug (sprintf "Executing %s" sql));
  let rec run count =
    match S3.step stmt with
    | Rc.DONE -> S3.changes db
    | (Rc.BUSY as code) | (Rc.LOCKED as code) ->
      begin match count <= retry with
        | true ->
          async (fun () -> Logger.warning (sprintf "Retrying execution [%s]" (Rc.to_string code)));
          Thread.yield ();
          run (count + 1)
        | false ->
          failwith (sprintf "Execution failed after %d retries with code [%s]" retry (Rc.to_string code))
      end
    | code ->
      failwith (sprintf "Execution failed with code [%s]" (Rc.to_string code))
  in
  let result = run 1 in
  clean_sync ~destroy stmt;
  result

let execute db ~destroy stmt =
  Lwt_preemptive.detach (fun () ->
    exec_sync db.db ~destroy stmt
  ) ()

type _ repr =
  | FBlobRowid : string repr
  | FBlobInt64 : (string * int64) repr
  | FText: string repr
  | FInt64 : int64 repr
  | Wrapped : Data.t array repr

let query : type a. t -> ?retry:int -> destroy:bool -> S3.stmt * string -> a repr -> (a array * int64 option) Lwt.t =
  fun db ?(retry=default_retries) ~destroy (stmt, sql) repr ->
    Lwt_preemptive.detach (fun () ->
      async (fun () -> Logger.debug (sprintf "Querying %s" sql));
      let queue : a Queue.t = Queue.create ~capacity:db.avg_read () in
      let rec run count last_rowid =
        match S3.step stmt with
        | Rc.ROW ->
          let last_rowid = begin match repr with
            | FBlobRowid ->
              begin match ((S3.column stmt 0), (S3.column stmt 1)) with
                | ((Data.BLOB blob), Data.INT rowid) -> Queue.enqueue queue blob; (Some rowid)
                | (data1, data2) -> failwith (sprintf "Querying failed (FBlobRowid, invalid datatypes [%s] and [%s], expected BLOB and INT" (Data.to_string_debug data1) (Data.to_string_debug data2))
              end
            | FBlobInt64 ->
              begin match ((S3.column stmt 0), (S3.column stmt 1)) with
                | ((Data.BLOB id), Data.INT timens) -> Queue.enqueue queue (id, timens); last_rowid
                | (data1, data2) -> failwith (sprintf "Querying failed (FBlobInt64), invalid datatypes [%s] and [%s], expected BLOB and INT" (Data.to_string_debug data1) (Data.to_string_debug data2))
              end
            | FInt64 ->
              begin match S3.column stmt 0 with
                | Data.INT i -> Queue.enqueue queue i; last_rowid
                | datatype -> failwith (sprintf "Querying failed, invalid datatype [%s], expected INT" (Data.to_string_debug datatype))
              end
            | FText ->
              begin match S3.column stmt 0 with
                | Data.TEXT str -> Queue.enqueue queue str; last_rowid
                | datatype -> failwith (sprintf "Querying failed, invalid datatype [%s], expected TEXT" (Data.to_string_debug datatype))
              end
            | Wrapped -> Queue.enqueue queue (S3.row_data stmt); last_rowid
          end in
          run 1 last_rowid
        | Rc.DONE ->
          clean_sync ~destroy stmt;
          last_rowid
        | (Rc.BUSY as code) | (Rc.LOCKED as code) ->
          begin match count <= retry with
            | true ->
              async (fun () -> Logger.warning (sprintf "Retrying query [%s]" (Rc.to_string code)));
              Thread.yield ();
              run (count + 1) last_rowid
            | false ->
              failwith (sprintf "Querying failed after %d retries with code [%s]" retry (Rc.to_string code))
          end
        | code ->
          failwith (sprintf "Querying failed with code [%s] [%s]" (Rc.to_string code) (S3.errmsg db.db))
      in
      let last_rowid = run 1 None in
      ((Queue.to_array queue), last_rowid)
    ) ()

let transaction db ~destroy ?query stmts =
  Lwt_preemptive.detach (fun () ->
    ignore (exec_sync db.db ~destroy:false db.stmts.begin_transaction);
    try
      let total_changed = List.fold stmts ~init:0 ~f:(fun acc stmt ->
          let changed = exec_sync db.db ~destroy stmt in
          acc + changed
        )
      in
      ignore (exec_sync db.db ~destroy:false db.stmts.commit_transaction);
      total_changed
    with
    | ex ->
      async (fun () -> Logger.error (Exception.full ex));
      exec_sync db.db ~destroy:false db.stmts.rollback_transaction
  ) ()

let prepare db sql =
  Lwt_preemptive.detach (fun () ->
    ((S3.prepare db sql), sql)
  ) ()

let bind ?(retry=default_retries) stmt args =
  Lwt_preemptive.detach (fun () ->
    let rec run pos arg count =
      match S3.bind stmt pos arg with
      | Rc.OK -> ()
      | (Rc.BUSY as code) | (Rc.LOCKED as code) ->
        begin match count <= retry with
          | true ->
            async (fun () -> Logger.warning (sprintf "Retrying bind [%s]" (Rc.to_string code)));
            Thread.yield ();
            run pos arg (count + 1)
          | false ->
            failwith (sprintf "Bind failed after %d retries with code [%s]" retry (Rc.to_string code))
        end
      | code ->
        failwith (sprintf "Bind failed with code [%s]" (Rc.to_string code))
    in
    Array.iter ~f:(fun (i, arg) -> run i arg 1) args
  ) ()

(***********
   SQL BUILDERS
 ***********)
let create_table_sql = "CREATE TABLE IF NOT EXISTS MESSAGES (uuid BLOB NOT NULL, timens BIGINT NOT NULL, raw BLOB NOT NULL, tag BLOB NULL, PRIMARY KEY(uuid));"
let create_timens_index_sql = "CREATE INDEX IF NOT EXISTS MESSAGES_TIMENS_IDX ON MESSAGES (timens);"
let create_tag_index_sql = "CREATE INDEX IF NOT EXISTS MESSAGES_TAG_IDX ON MESSAGES (tag);"

let make_filters filters =
  let strings = Array.map filters ~f:(fun filter ->
      match filter with
      | `After_id _ -> "(ROWID > (SELECT ROWID FROM MESSAGES WHERE uuid = ?))"
      | `After_ts _ -> "(timens > ?)"
      | `After_rowid _ -> "(ROWID > ?)"
      | `Tag _ -> "(tag = ?)"
    ) in
  String.concat_array ~sep:" AND " strings

let read_sql ~search =
  let open Search in
  match search.filters with
  | [| |] -> sprintf "SELECT raw, ROWID FROM MESSAGES LIMIT %Ld;" search.limit
  | _ -> sprintf "SELECT raw, ROWID FROM MESSAGES WHERE %s LIMIT %Ld;" (make_filters search.filters) search.limit

let add_tag_sql ~search =
  let open Search in
  match search.filters with
  | [| |] -> sprintf "UPDATE MESSAGES SET tag = ? LIMIT %Ld;" search.limit
  | _ -> sprintf "UPDATE MESSAGES SET tag = ? WHERE %s LIMIT %Ld;" (make_filters search.filters) search.limit

let read_tag_sql = "SELECT raw, ROWID FROM MESSAGES INDEXED BY MESSAGES_TAG_IDX WHERE (tag = ?);"
let delete_tag_sql = "DELETE FROM MESSAGES INDEXED BY MESSAGES_TAG_IDX WHERE (tag = ?);"

let last_row_sql = "SELECT uuid, timens FROM MESSAGES WHERE ROWID = ?;"
let count_sql = "SELECT COUNT(*) FROM MESSAGES;"
let begin_sql = "BEGIN;"
let commit_sql = "COMMIT;"
let rollback_sql = "ROLLBACK;"
let truncate_sql = "DELETE FROM MESSAGES;"
let quick_check_sql = "PRAGMA quick_check;"
let insert_sql count =
  let arr = Array.create ~len:count "(?,?,?)" in
  sprintf "INSERT OR IGNORE INTO MESSAGES (uuid,timens,raw) VALUES %s;" (String.concat_array ~sep:"," arr)

(*******************
   HIGH LEVEL FUNCTIONS
 *******************)
let create file ~avg_read =
  let%lwt db = wrap (fun () -> S3.db_open file) in

  (* These queries directly call exec_sync because the instance doesn't yet exist *)
  let%lwt create_table = prepare db create_table_sql in
  let%lwt (_ : int) = wrap (fun () -> exec_sync db ~destroy:false create_table) in
  let%lwt create_timens_index = prepare db create_timens_index_sql in
  let%lwt (_ : int) = wrap (fun () -> exec_sync db ~destroy:false create_timens_index) in
  let%lwt create_tag_index = prepare db create_tag_index_sql in
  let%lwt (_ : int) = wrap (fun () -> exec_sync db ~destroy:false create_tag_index) in

  let%lwt last_row = prepare db last_row_sql in
  let%lwt count = prepare db count_sql in
  let%lwt begin_transaction = prepare db begin_sql in
  let%lwt commit_transaction = prepare db commit_sql in
  let%lwt rollback_transaction = prepare db rollback_sql in
  let%lwt truncate = prepare db truncate_sql in
  let%lwt quick_check = prepare db quick_check_sql in

  let stmts = {last_row; count; begin_transaction; commit_transaction; rollback_transaction; truncate; quick_check} in
  let instance = {db; file; avg_read; stmts} in
  return instance

let close db =
  let rec aux ?(retry=default_retries) count =
    match count <= retry with
    | true ->
      begin match%lwt wrap (fun () -> S3.db_close db.db) with
        | true -> return_unit
        | false ->
          let%lwt () = Logger.warning "Retrying db_close" in
          aux (count + 1)
      end
    | false -> fail_with "Could not close db"
  in
  aux 0

let push db ~msgs ~ids =
  let time = Util.time_ns_int64 () in
  let make_stmt slice =
    let%lwt (st, _) as stmt = prepare db.db (insert_sql (Array.length slice)) in
    let args = Array.concat_mapi slice ~f:(fun i (raw, id) ->
        let pos = i * 3 in
        [| ((pos + 1), Data.BLOB id); ((pos + 2), Data.INT time); ((pos + 3), Data.BLOB raw) |]
      )
    in
    let%lwt () = bind st args in
    return stmt
  in
  match%lwt Util.zip_group ~size:insert_batch_size msgs ids with
  | (group::[]) ->
    let%lwt stmt = make_stmt group in
    execute db ~destroy:true stmt
  | groups ->
    let%lwt stmts = Lwt_list.map_s make_stmt groups in
    transaction db ~destroy:true stmts

let make_args filters =
  Array.mapi filters ~f:(fun i filter ->
    match filter with
    | `After_id id -> ((i + 1), Data.BLOB id)
    | `After_ts ts -> ((i + 1), Data.INT ts)
    | `After_rowid rowid -> ((i + 1), Data.INT rowid)
    | `Tag tag -> ((i + 1), Data.BLOB tag)
  )

let fetch_last_row db ~rowid =
  let (st, sql) as stmt = db.stmts.last_row in
  let args = [| (1, Data.INT rowid) |] in
  let%lwt () = bind st args in
  match%lwt query db ~destroy:false stmt FBlobInt64 with
  | [| x |], _ -> return x
  | dataset, _ -> fail_with (sprintf "Last_row failed (dataset size: %d) for %s" (Array.length dataset) sql)

let pull db ~search ~fetch_last =
  let open Search in
  match search.only_once with
  | true ->
    let tag = Id.uuid () in

    (* Add tag *)
    let%lwt (st, _) as stmt = prepare db.db (add_tag_sql ~search) in
    let args = make_args (Array.append [| `Tag tag |] search.filters) in
    let%lwt () = bind st args in
    let%lwt cnt1 = execute db ~destroy:true stmt in

    (* Select tag *)
    let%lwt (st, _) as stmt = prepare db.db read_tag_sql in
    let args = make_args [| `Tag tag |] in
    let%lwt () = bind st args in
    let%lwt (rows, last_rowid) = query db ~destroy:false stmt FBlobRowid in
    let cnt2 = Array.length rows in

    (* Get last row if necessary *)
    let%lwt last_row_data = begin match (fetch_last, last_rowid) with
      | (false, _) | (true, None) -> return_none
      | (true, Some rowid) ->
        map Option.some (fetch_last_row db ~rowid)
    end
    in

    (* Delete tag *)
    let%lwt (st, _) as stmt = prepare db.db delete_tag_sql in
    let args = make_args [| `Tag tag |] in
    let%lwt () = bind st args in
    let%lwt cnt3 = execute db ~destroy:false stmt in

    if cnt1 <> cnt2 || cnt2 <> cnt3 then
      let err = (sprintf "Impossible state, returned counts differ: [%d] [%d] [%d]. This bug should be reported." cnt1 cnt2 cnt3) in
      let%lwt () = Logger.fatal err in
      fail_with err
    else
      return (rows, last_rowid, last_row_data)

  | false ->
    (* Just SELECT *)
    let%lwt (st, _) as stmt = prepare db.db (read_sql ~search) in
    let args = make_args search.filters in
    let%lwt () = bind st args in
    let%lwt (rows, last_rowid) = query db ~destroy:true stmt FBlobRowid in

    (* Get last row if necessary *)
    let%lwt last_row_data = begin match (fetch_last, last_rowid) with
      | (false, _) | (true, None) -> return_none
      | (true, Some rowid) ->
        map Option.some (fetch_last_row db ~rowid)
    end
    in
    return (rows, last_rowid, last_row_data)

let size db =
  let (_, sql) as stmt = db.stmts.count in
  match%lwt query db ~destroy:false stmt FInt64 with
  | [| x |], _ -> return x
  | dataset, _ -> fail_with (sprintf "Count failed (dataset size: %d)" (Array.length dataset))

let delete db =
  let (_, sql) as stmt = db.stmts.truncate in
  let%lwt (_ : int) = execute db ~destroy:false stmt in
  return_unit

let health db =
  let (_, sql) as stmt = db.stmts.quick_check in
  match%lwt query db ~destroy:false stmt FText with
  | [| "ok" |], _ -> return []
  | [| str |], _ -> return [sprintf "Local Health failure: %s" str]
  | dataset, _ -> fail_with (
      sprintf
        "Health failed (dataset size: %d) with %s"
        (Array.length dataset) (String.concat_array ~sep:", " dataset)
    )
