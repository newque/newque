type t =
  | Production
  | Development

val create : Config_t.config_environment -> t

val to_string : t -> string
