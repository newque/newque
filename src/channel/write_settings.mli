type ack =
  | Instant
  | Saved
[@@deriving sexp]

type t = {
  ack: ack;
  format: Io_format.t;
  copy_to: string list;
} [@@deriving sexp]

val create : Config_t.config_channel_write -> t
