open Core.Std
open Lwt

type memory_t = {
  db: unit;
  chan_name: string;
  mutex: Mutex.t sexp_opaque;
} [@@deriving sexp]

let create ~chan_name ~avg_read =
  let db = () in
  let instance = {db; chan_name; mutex = Mutex.create ();} in
  return instance

module M = struct

  type t = memory_t [@@deriving sexp]

  let close instance = return_unit

  let push instance ~msgs ~ids ack =
    return 1

  let pull instance ~mode =
    return [| |]

  let size instance =
    return 20

end
