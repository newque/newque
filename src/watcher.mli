open Core.Std

type t = {
  router: Router.t;
  listeners : Listener.t Int.Table.t;
}

val create : Router.t -> t

val monitor : t -> Listener.t -> unit Conduit_lwt_unix.io

val create_listeners : t -> Config_t.config_listener list -> Listener.t list Conduit_lwt_unix.io
