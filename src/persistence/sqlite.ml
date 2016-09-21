open Core.Std
open Lwt
(* Not opening Sqlite3, to make it more explicit and to wrap all calls to it *)
module S3 = Sqlite3
module Rc = Sqlite3.Rc
module Data = Sqlite3.Data

module Logger = Log.Make (struct let path = Log.outlog let section = "Sqlite" end)

type statements = {
  count: Sqlite3.stmt * string;
  read_one: Sqlite3.stmt * string;
  begin_transaction: Sqlite3.stmt * string;
  commit_transaction: Sqlite3.stmt * string;
  rollback_transaction: Sqlite3.stmt * string;
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
let default_retries = 10

  #ifdef DEBUG
let batch_size = 2
  #else
let batch_size = 100
  #endif

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
        ignore (async (fun () -> Logger.error (Exn.to_string ex)));
        S3.recompile stmt
    end

let exec_sync db ?(retry=default_retries) ~destroy (stmt, sql) =
  ignore (async (fun () -> Logger.debug_lazy (lazy (Printf.sprintf "Executing %s" sql))));
  let rec run count =
    match S3.step stmt with
    | Rc.DONE -> S3.changes db
    | (Rc.BUSY as code) | (Rc.LOCKED as code) ->
      begin match count <= retry with
        | true ->
          ignore (async (fun () -> Logger.warning (Printf.sprintf "Retrying execution (%s)" (Rc.to_string code))));
          Thread.yield ();
          run (count + 1)
        | false ->
          failwith (Printf.sprintf "Execution failed after %d retries with code %s" retry (Rc.to_string code))
      end
    | code ->
      failwith (Printf.sprintf "Execution failed with code %s" (Rc.to_string code))
  in
  let result = run 1 in
  clean_sync ~destroy stmt;
  result

let execute db ~destroy stmt =
  Lwt_preemptive.detach (fun () ->
    exec_sync db.db ~destroy stmt
  ) ()

type _ repr =
  | FBlob : string repr
  | FInt64 : int64 repr
  | Wrapped : Data.t array repr

let query : type a. t -> ?retry:int -> destroy:bool -> S3.stmt * string -> a repr -> a array Lwt.t =
  fun db ?(retry=default_retries) ~destroy (stmt, sql) repr ->
    Lwt_preemptive.detach (fun () ->
      ignore (async (fun () -> Logger.debug_lazy (lazy (Printf.sprintf "Querying %s" sql))));
      let queue : a Queue.t = Queue.create ~capacity:db.avg_read () in
      let rec run count =
        match S3.step stmt with
        | Rc.ROW ->
          begin match repr with
            | FBlob ->
              begin match S3.column stmt 0 with
                | Data.BLOB blob -> Queue.enqueue queue blob
                | datatype -> failwith (Printf.sprintf "Querying failed, invalid datatype %s, expected BLOB" (Data.to_string_debug datatype))
              end
            | FInt64 ->
              begin match S3.column stmt 0 with
                | Data.INT i -> Queue.enqueue queue i
                | datatype -> failwith (Printf.sprintf "Querying failed, invalid datatype %s, expected INT" (Data.to_string_debug datatype))
              end
            | Wrapped -> Queue.enqueue queue (S3.row_data stmt)
          end;
          run 0
        | Rc.DONE -> ()
        | (Rc.BUSY as code) | (Rc.LOCKED as code) ->
          begin match count <= retry with
            | true ->
              ignore (async (fun () -> Logger.warning (Printf.sprintf "Retrying query (%s)" (Rc.to_string code))));
              Thread.yield ();
              run (count + 1)
            | false ->
              failwith (Printf.sprintf "Querying failed after %d retries with code %s" retry (Rc.to_string code))
          end
        | code ->
          failwith (Printf.sprintf "Querying failed with code %s" (Rc.to_string code))
      in
      let () = run 1 in
      clean_sync ~destroy stmt;
      Queue.to_array queue
    ) ()

let transaction db ~destroy stmts =
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
      ignore (async (fun () -> Logger.error (Exn.to_string ex)));
      exec_sync db.db ~destroy:false db.stmts.rollback_transaction
  ) ()

let prepare db sql =
  Lwt_preemptive.detach (fun () ->
    ((S3.prepare db sql), sql)
  ) ()

let bind db ?(retry=default_retries) stmt args =
  Lwt_preemptive.detach (fun () ->
    let rec run pos arg count =
      match S3.bind stmt pos arg with
      | Rc.OK -> ()
      | (Rc.BUSY as code) | (Rc.LOCKED as code) ->
        begin match count <= retry with
          | true ->
            ignore (async (fun () -> Logger.warning (Printf.sprintf "Retrying bind (%s)" (Rc.to_string code))));
            Thread.yield ();
            run pos arg (count + 1)
          | false ->
            failwith (Printf.sprintf "Bind failed after %d retries with code %s" retry (Rc.to_string code))
        end
      | code ->
        failwith (Printf.sprintf "Bind failed with code %s" (Rc.to_string code))
    in
    Array.iter ~f:(fun (i, arg) -> run i arg 0) args
  ) ()

let create_table_sql = "CREATE TABLE IF NOT EXISTS MESSAGES (uuid BLOB NOT NULL, timens BIGINT NOT NULL, raw BLOB NOT NULL, PRIMARY KEY(uuid));"
let create_timens_index_sql = "CREATE INDEX IF NOT EXISTS MESSAGES_TIMENS_IDX ON MESSAGES (timens);"
let read_one_sql = "SELECT raw FROM MESSAGES ORDER BY ROWID ASC LIMIT 1;"
let read_many_sql count =
  Printf.sprintf "SELECT raw FROM MESSAGES ORDER BY ROWID ASC LIMIT %d;" count
let count_sql = "SELECT COUNT(*) FROM MESSAGES;"
let begin_sql = "BEGIN;"
let commit_sql = "COMMIT;"
let rollback_sql = "ROLLBACK;"
let insert_sql count =
  let arr = Array.create ~len:count "(?,?,?)" in
  Printf.sprintf "INSERT OR IGNORE INTO MESSAGES (uuid,timens,raw) VALUES %s;" (String.concat_array ~sep:"," arr)

let create file ~avg_read =
  let%lwt db = wrap (fun () -> S3.db_open file) in

  (* These queries directly call exec_sync because the instance doesn't yet exist *)
  let%lwt create_table = prepare db create_table_sql in
  let%lwt (_ : int) = wrap (fun () -> exec_sync db ~destroy:false create_table) in
  let%lwt create_timens_index = prepare db create_timens_index_sql in
  let%lwt (_ : int) = wrap (fun () -> exec_sync db ~destroy:false create_timens_index) in

  let%lwt count = prepare db count_sql in
  let%lwt read_one = prepare db read_one_sql in
  let%lwt begin_transaction = prepare db begin_sql in
  let%lwt commit_transaction = prepare db commit_sql in
  let%lwt rollback_transaction = prepare db rollback_sql in

  let stmts = {count; read_one; begin_transaction; commit_transaction; rollback_transaction} in
  let instance = {db; file; avg_read; stmts} in
  return instance

let close db =
  let rec aux ?(retry=default_retries) count =
    match count <= retry with
    | true ->
      begin match%lwt wrap (fun () -> S3.db_close db.db) with
        | true -> return_unit
        | false ->
          let%lwt () = Logger.warning "Retrying db_close." in
          aux (count + 1)
      end
    | false -> fail_with "Could not close db."
  in
  aux 0

let push db ~msgs ~ids =
  let time = Id.time_ns () in
  let make_stmt slice =
    let%lwt ((st, _) as stmt) = prepare db.db (insert_sql (Array.length slice)) in
    let args = Array.concat_mapi slice ~f:(fun i (raw, id) ->
        let pos = i * 3 in
        [| ((pos + 1), Data.BLOB id); ((pos + 2), Data.INT time); ((pos + 3), Data.BLOB raw) |]
      )
    in
    let%lwt () = bind db st args in
    return stmt
  in
  match%lwt Util.zip_group ~size:batch_size msgs ids with
  | (group::[]) ->
    let%lwt stmt = make_stmt group in
    execute db ~destroy:true stmt
  | groups ->
    let%lwt stmts = Lwt_list.map_s make_stmt groups in
    transaction db ~destroy:true stmts

let pull db ~mode =
  match mode with
  | `One ->
    begin match%lwt query db ~destroy:false db.stmts.read_one FBlob with
      | ([| |] as x) | ([| _ |] as x) -> return x
      | dataset -> failwith (Printf.sprintf "Select One failed for %s, dataset size: %d" db.file (Array.length dataset))
    end
  | `Many count ->
    let%lwt stmt = prepare db.db (read_many_sql count) in
    query db ~destroy:true stmt FBlob
  | _ -> return [| |]

let size db =
  match%lwt query db ~destroy:false db.stmts.count FInt64 with
  | [| x |] -> return x
  | dataset -> failwith (Printf.sprintf "Count failed for %s, dataset size: %d" db.file (Array.length dataset))
