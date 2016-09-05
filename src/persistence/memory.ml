open Core.Std
open Lwt
open Sexplib.Conv

type memory_t = {
  db: unit;
  tablename: string;
  mutex: Mutex.t sexp_opaque;
} [@@deriving sexp]

let create tablename =
  let db = () in
  let instance = {db; tablename; mutex = Mutex.create ();} in
  return instance

module M = struct

  type t = memory_t [@@deriving sexp]

  let close (pers : t) = return_unit

  let push (pers : t) ~chan_name (msg : Message.t) (ack : Ack.t) =
    return 1

  let size (pers : t) =
    return 20

end
