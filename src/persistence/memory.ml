open Core.Std
open Lwt

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

  let close (instance : t) = return_unit

  let push (instance : t) ~msgs ~ids ack =
    return 1

  let size (instance : t) =
    return 20

end
