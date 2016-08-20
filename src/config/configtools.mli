open Core.Std

val parse_main : string -> Config_t.config_newque Lwt.t

val apply_main : Config_t.config_newque -> Watcher.t -> Listener.t list Lwt.t

val parse_channels : string -> Channel.t list Lwt.t

val apply_channels : Channel.t list -> Listener.t list -> Router.t -> (unit, string list) Result.t
