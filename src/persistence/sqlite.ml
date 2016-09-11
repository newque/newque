open Core.Std
open Lwt
(* Not opening Sqlite3, to make it more explicit and to wrap all calls to it *)
module S3 = Sqlite3
module Rc = Sqlite3.Rc
module Data = Sqlite3.Data

module Logger = Log.Make (struct let path = Log.outlog let section = "Sqlite" end)

type statements = {
  create_table: Sqlite3.stmt * string;
}
type t = {
  db: Sqlite3.db sexp_opaque;
  file: string;
  stmts: statements sexp_opaque;
} [@@deriving sexp]

(* Ridiculously high number of retries by default,
   because it is only retried when the db is locked.
   We only want it to fail in catastrophic cases. *)
let default_retries = 50

let is_success rc =
  match rc with
  | Rc.OK -> true
  | _ -> false

let run_ignore ~str thunk =
  let%lwt rc = wrap thunk in
  if is_success rc then
    return_unit
  else
    Logger.warning (Printf.sprintf "Operation %s failed with code %s" str (Rc.to_string rc))

let execute ?(retry=default_retries) ~destroy (stmt, sql) =
  let%lwt () = Logger.debug_lazy (lazy (Printf.sprintf "Executing %s" sql)) in
  let rec run count =
    match S3.step stmt with
    | Rc.DONE -> ()
    | (Rc.BUSY as code) | (Rc.LOCKED as code) ->
      begin match count <= retry with
        | true ->
          ignore_result (Logger.debug "Retrying execution");
          Thread.yield ();
          run (count + 1)
        | false ->
          failwith (Printf.sprintf "Execution failed after %d retries with code %s" retry (Rc.to_string code))
      end
    | code ->
      failwith (Printf.sprintf "Execution failed with code %s" (Rc.to_string code))
  in
  let%lwt result = wrap (fun () -> run 1) in
  let%lwt () = begin match destroy with
    | true -> run_ignore ~str:"Finalize Statement" (fun () -> S3.finalize stmt)
    | false -> begin
        try%lwt
          let%lwt rc = wrap (fun () -> S3.reset stmt) in
          if not (is_success rc) then
            fail_with "Failed to Reset Statement"
          else
            return_unit
        with
        | ex -> wrap (fun () -> S3.recompile stmt)
      end
  end in
  return result

let prepare db sql =
  match S3.prepare db sql with
  | exception ex -> fail ex
  | stmt -> return (stmt, sql)

let bind ?(retry=default_retries) stmt pos arg =
  let rec run count =
    match S3.bind stmt pos arg with
    | Rc.OK -> ()
    | (Rc.BUSY as code) | (Rc.LOCKED as code) ->
      begin match count <= retry with
        | true ->
          ignore_result (Logger.debug "Retrying bind");
          Thread.yield ();
          run (count + 1)
        | false ->
          failwith (Printf.sprintf "Bind failed after %d retries with code %s" retry (Rc.to_string code))
      end
    | code ->
      failwith (Printf.sprintf "Bind failed with code %s" (Rc.to_string code))
  in
  wrap (fun () -> run 1)

(* let transaction thunks =
   let rec run result thunks =
    match thunks with
    | [] -> result
    | thunk::rest ->

   in
   run (Ok ()) thunks *)

let create_table_sql = "CREATE TABLE IF NOT EXISTS MESSAGES (uuid BLOB NOT NULL, timens BIGINT NOT NULL, raw BLOB NOT NULL, PRIMARY KEY(uuid));"
let insert_sql count =
  let arr = Array.create ~len:count "(?,?,?)" in
  Printf.sprintf "INSERT INTO MESSAGES (uuid,timens,raw) VALUES %s" (String.concat_array ~sep:"," arr)

let create file =
  let%lwt db = wrap (fun () -> S3.db_open file) in
  let%lwt create_table = prepare db create_table_sql in
  let%lwt () = execute ~destroy:true create_table in

  let stmts = {create_table} in
  return {db; file; stmts;}

let insert db ~msgs ~ids =
  let time = Id.time_ns () in
  let run slice =
    let%lwt ((st, _) as stmt) = prepare db.db (insert_sql (List.length slice)) in
    let%lwt () = Lwt_list.iteri_s (fun i (raw, id) ->
        let pos = i * 3 in
        let uuid_data = Data.BLOB id in
        let timens_data = Data.INT time in
        let raw_data = Data.BLOB raw in
        let%lwt () = bind st (pos+1) uuid_data in
        let%lwt () = bind st (pos+2) timens_data in
        bind st (pos+3) raw_data
      ) slice in
    execute ~destroy:true stmt
  in
  let%lwt divided = Util.rev_zip_group ~size:2 msgs ids in
  let%lwt () = Lwt_list.iter_s run divided in
  return (List.length msgs)







