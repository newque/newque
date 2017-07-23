open Core

type t

val create : Environment.t -> t

val router : t -> Router.t
val table : t -> Listener.t Int.Table.t
val listeners : t -> Listener.t list

val listeners_to_json : t -> int option -> Yojson.Basic.json

val monitor : t -> Listener.t -> unit Lwt.t

val create_listeners : t -> Config_t.config_listener list -> unit Lwt.t

val create_admin_server : t -> Config_t.config_newque -> (Http_prot.t * string) Lwt.t
