open Core.Std
open Lwt
open Sexplib.Conv

type memory_t = {
  db: unit;
  tablename: string;
} [@@deriving sexp]

let create tablename =
  let instance = {db = (); tablename;} in
  return instance

module M = struct

  type t = memory_t [@@deriving sexp]

  let close (pers : t) = return_unit

  let push_single (pers : t) ~chan_name (msg : Message.t) (ack : Ack.t) =
    return 1

  let push_atomic (pers : t) ~chan_name (msgs : Message.t list) (ack : Ack.t) =
    return 5

  let size (pers : t) =
    return 20

end
