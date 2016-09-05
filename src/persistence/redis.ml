open Core.Std
open Lwt
open Sexplib.Conv

type redis_t = {
  conn: unit;
  host: string;
  port: int;
  auth: string option;
} [@@deriving sexp]

let create host port auth =
  let instance = {conn = (); host; port; auth;} in
  return instance

module M = struct

  type t = redis_t [@@deriving sexp]

  let close (conf : t) = return_unit

  let push_single (pers : t) ~chan_name (msg : Message.t) (ack : Ack.t) =
    return 1

  let push_atomic (pers : t) ~chan_name (msgs : Message.t list) (ack : Ack.t) =
    return 5

  let size (pers : t) =
    return 20

end
