open Core.Std

type server =
  | HTTP of Http.t * unit Lwt.u
  | ZMQ of unit * unit Lwt.u

type listener = { id : string; server : server; }

type t = { listeners : listener Int.Table.t; }

val create : unit -> t

val monitor : listener -> unit Conduit_lwt_unix.io

val add_listeners : t -> Config_j.ext_listener list -> listener list Conduit_lwt_unix.io
