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

(* Ridiculously high number of retries by default,
   because it is only retried when the db is locked.
   We only want it to fail in catastrophic cases. *)
let execute ?(retry=50) ~destroy (stmt, sql) =
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
  let result = wrap (fun () -> run 1) in
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
  result

let prepare db sql =
  match S3.prepare db sql with
  | exception ex -> fail ex
  | stmt -> return (stmt, sql)

(* Ridiculously high number of retries by default,
   because it is only retried when the db is locked.
   We only want it to fail in catastrophic cases. *)
let bind ?(retry=50) stmt pos arg =
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

let create_table_sql = "CREATE TABLE IF NOT EXISTS MESSAGES (timens BIGINT NOT NULL, raw BLOB NOT NULL)"
let insert_sql count =
  let arr = Array.create ~len:count "(?,?)" in
  Printf.sprintf "INSERT INTO MESSAGES (timens, raw) VALUES %s;" (String.concat_array ~sep:"," arr)

let create file =
  let%lwt db = wrap (fun () -> S3.db_open file) in
  let%lwt create_table = prepare db create_table_sql in
  let%lwt () = execute ~destroy:true create_table in

  let stmts = {create_table} in
  return {db; file; stmts;}

let get_time () = Time_ns.now () |> Time_ns.to_int63_ns_since_epoch |> Int63.to_int64

let insert db blobs =
  let%lwt () = Logger.info "Inserting!" in
  let run slice =
    let%lwt () = Logger.info ("Inserting " ^ (Int.to_string (List.length slice))) in
    let time = get_time () in
    let%lwt ((st, _) as stmt) = prepare db.db (insert_sql (List.length slice)) in
    let%lwt () = Lwt_list.iteri_s (fun i raw ->
        let%lwt () = bind st (i+1) (Data.INT time) in
        bind st (i+2) (Data.BLOB raw)
      ) slice in
    execute ~destroy:true stmt
  in
  let divided = List.groupi blobs ~break:(fun i _ _ -> i mod 100 = 0) in
  let%lwt () = Lwt_list.iter_p run divided in
  return (List.length blobs)







