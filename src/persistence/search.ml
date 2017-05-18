open Core

type t = {
  limit: int64;
  filters: [ `After_id of string | `After_ts of int64 | `After_rowid of int64 | `Tag of string ] array;
  only_once: bool;
}

let create max_read ~mode ~only_once =
  match mode with
  | `One -> { limit = Int64.one; filters = [| |]; only_once; }
  | `Many x -> { limit = (Int64.min max_read x); filters = [| |]; only_once; }
  | `After_id id -> { limit = max_read; filters = [|`After_id id|]; only_once; }
  | `After_ts ts -> { limit = max_read; filters = [|`After_ts ts|]; only_once; }

let mode_and_limit search = match search with
  | { filters = [| ((`After_id _) as mode) |]; limit; _ }
  | { filters = [| ((`After_ts _) as mode) |]; limit; _ } -> (mode, limit)
  | { limit; _ } -> ((`Many limit), limit)
