type ack =
  | Instant
  | Saved
[@@deriving sexp]

type batching = {
  max_time: float;
  max_size: int;
} [@@deriving sexp]

type t = {
  http_format: Http_format.t;
  ack: ack;
  copy_to: string list;
  batching: batching option;
} [@@deriving sexp]

val create : Config_t.config_channel_write -> t
