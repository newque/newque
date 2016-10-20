type format =
  | Plaintext
  | Json
[@@deriving sexp]

type t = {
  format: format;
} [@@deriving sexp]

val create : Config_t.config_channel_read -> t
