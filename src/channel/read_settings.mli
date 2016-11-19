type t = {
  format: Io_format.t;
  stream_slice_size: int64;
  only_once: bool;
} [@@deriving sexp]

val create : Config_t.config_channel_read -> t
