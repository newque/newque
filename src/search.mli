type t = {
  limit: int64;
  filters: [ `After_id of string | `After_ts of int64 | `After_rowid of int64 | `Tag of string ] array;
  only_once: bool;
} [@@deriving sexp]

val create : int64 -> mode:Mode.Read.t -> only_once:bool -> t

val mode_and_limit : t -> Mode.Read.t * int64
