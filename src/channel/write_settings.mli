type ack =
  | Instant
  | Saved
[@@deriving sexp]

type t = {
  ack: ack;
} [@@deriving sexp]

val create : Config_t.config_channel_write -> t
