type t = {
  format: Io_format.t;
} [@@deriving sexp]

val create : Config_t.config_channel_read -> t
