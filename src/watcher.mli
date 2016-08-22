open Core.Std

type t

val create : unit -> t

val router : t -> Router.t
val listeners : t -> Listener.t list

val monitor : t -> Listener.t -> unit Lwt.t

val create_listeners : t -> Config_t.config_listener list -> unit Lwt.t
