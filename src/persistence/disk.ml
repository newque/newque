open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Disk" end)

type disk_t = {
  db: Sqlite.t;
  file: string;
  tablename: string;
} [@@deriving sexp]

let create dir tablename =
  let file = Printf.sprintf "%s%s.data" dir tablename in
  let%lwt () = Logger.info (Printf.sprintf "Initializing %s" file) in
  let%lwt db = Sqlite.create file in
  let instance = {db; file; tablename;} in
  return instance

module M = struct

  type t = disk_t [@@deriving sexp]

  let close (pers : t) = return_unit

  let push (pers : t) ~chan_name (msgs : Message.t list) (ack : Ack.t) =
    print_endline (pers.file ^ "  PUSH!! ");

    print_endline (List.sexp_of_t Message.sexp_of_t msgs |> Log.str_of_sexp);

    Sqlite.insert pers.db (List.map ~f:Message.serialize msgs)

  let size (pers : t) =
    return 21

end
