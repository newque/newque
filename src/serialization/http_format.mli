type t =
  | Plaintext
  | Json
[@@deriving sexp]

val create : Config_t.config_channel_format -> t
