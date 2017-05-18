open Core

val parse_main : string -> Config_t.config_newque Lwt.t

val apply_main : Config_t.config_newque -> Watcher.t -> unit Lwt.t

val parse_channels : Config_t.config_newque -> string -> Channel.t list Lwt.t

val apply_channels : Watcher.t -> Channel.t list -> (unit, string list) Result.t
