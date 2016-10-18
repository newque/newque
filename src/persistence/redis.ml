open Core.Std
open Lwt

type redis_t = {
  conn: unit;
  host: string;
  port: int;
  auth: string option;
} [@@deriving sexp]

#ifdef DEBUG
let read_batch_size = 2
  #else
let read_batch_size = 500
  #endif

let create host port auth =
  let instance = {conn = (); host; port; auth;} in
  return instance

module M = struct

  type t = redis_t [@@deriving sexp]

  let close instance = return_unit

  let push instance ~msgs ~ids ack =
    return 1

  let pull_slice instance ~search = fail_with "Unimplemented: Redis pull_slice"

  let pull_stream instance ~search = fail_with "Unimplemented: Redis pull_stream"

  let size instance =
    return (Int.to_int64 20)

end
