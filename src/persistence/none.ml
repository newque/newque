open Core.Std
open Lwt

type none_t = unit [@@deriving sexp]

let create () = return_unit

module M = struct

  type t = none_t [@@deriving sexp]

  let close instance = return_unit

  let push instance ~msgs ~ids = return Int.zero

  let pull instance ~search ~fetch_last = return ([||], None, None)

  let size instance = return Int64.zero

  let delete instance = return_unit

  let health instance = return []

end
