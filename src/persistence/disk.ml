open Core.Std
open Lwt
open Sexplib.Conv

type disk_t = {
  db: unit;
  dir: string;
  tablename: string;
} [@@deriving sexp]

let create dir tablename =
  let instance = {db = (); dir; tablename;} in
  return instance

module M = struct

  type t = disk_t [@@deriving sexp]

  let close (pers : t) = return_unit

  let return_one = return 1
  let push_single (pers : t) ~chan_name (msg : Message.t) (ack : Ack.t) =
    print_endline (pers.dir ^ "  single " ^ (Message.contents msg));
    return_one

  let push_atomic (pers : t) ~chan_name (msgs : Message.t list) (ack : Ack.t) =
    print_endline (pers.dir ^ "  atomic");
    return 6

  let size (pers : t) =
    return 21

end
