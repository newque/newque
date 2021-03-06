open Core
open Lwt

type none_t = unit

let create () = return_unit

module M = struct

  type t = none_t

  let close instance = return_unit

  let push instance ~msgs ~ids = return (Collection.length msgs)

  let pull instance ~search ~fetch_last = return (Collection.empty, None, None)

  let size instance = return Int64.zero

  let delete instance = return_unit

  let health instance = return []

end
