open Core.Std
open Lwt

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

  let close instance = return_unit

  let push instance ~msgs ~ids = fail_with "Invalid operation: Redis write"

  let pull instance ~search ~fetch_last = fail_with "Invalid operation: Redis read"

  let size instance = fail_with "Invalid operation: Redis count"

  let delete instance = fail_with "Invalid operation: Redis delete"

  let health instance = fail_with "Invalid operation: Redis health"

end
