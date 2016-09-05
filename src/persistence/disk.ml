open Core.Std
open Lwt
open Sexplib.Conv

module Logger = Log.Make (struct let path = Log.outlog let section = "Disk" end)

type disk_t = {
  db: Sqlite.t;
  file: string;
  tablename: string;
} [@@deriving sexp]

let create dir tablename =
  let file = Printf.sprintf "%s%s.data" dir tablename in
  let%lwt () = Logger.info (Printf.sprintf "Initializing %s" file) in
  let db = Sqlite.create ~tablenames:[tablename] file in
  let instance = {db; file; tablename;} in
  return instance

module M = struct

  type t = disk_t [@@deriving sexp]

  let close (pers : t) = return_unit

  let return_one = return 1
  let push (pers : t) ~chan_name (msg : Message.t) (ack : Ack.t) =
    print_endline (pers.file ^ "  PUSH!! ");
    return_one

  let size (pers : t) =
    return 21

end
