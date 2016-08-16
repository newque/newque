val parse_main : string -> Config_j.config Lwt.t

val apply_main : Config_j.config -> Watcher.t -> Watcher.listener list Lwt.t

val parse_channels : string -> Channel.t list Lwt.t
