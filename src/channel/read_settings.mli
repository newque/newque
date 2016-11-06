type t = {
  format: Io_format.t;
  only_once: bool;
} [@@deriving sexp]

val create : Config_t.config_channel_read -> t
