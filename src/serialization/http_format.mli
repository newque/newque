type t =
  | Plaintext
  | Json

val create : Config_t.config_channel_format -> t
