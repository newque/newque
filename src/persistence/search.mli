type t = {
  limit: int64;
  after_id: string option;
  after_ts: int64 option;
  after_rowid: int64 option;
  only_once: bool;
}

val create : int64 -> mode:Mode.Read.t -> only_once:bool -> t

val has_any_filters : t -> bool

val mode_and_limit : t -> Mode.Read.t * int64
