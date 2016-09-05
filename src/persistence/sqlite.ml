open Core.Std
open Sqlite3
open Sexplib.Conv

type t = Sqlite3.db sexp_opaque [@@deriving sexp]

(* Sqlite's C code has its own preemptive threading, this is not blocking. *)
let create ~tablenames file =
  let db = db_open file in
  db
(* let stmt = prepare db "CREATE TABLE IF NOT EXISTS MESSAGES (raw BLOB, createdat )" *)
