type after =
  | After_id of string
  | After_ts of int64
  | After_rowid of int64

type t = {
  limit: int64;
  after: after option;
  only_once: bool;
}

val create : int64 -> mode:Mode.Read.t -> only_once:bool -> t

val mode_and_limit : t -> Mode.Read.t * int64

val after_to_strings : t -> string * string
