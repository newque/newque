open Core
open Cohttp
open Cohttp_lwt_unix
open Routing

type t = {
  generic : Config_t.config_listener;
  specific : Config_t.config_http_settings;
  sock : Lwt_unix.file_descr;
  stop_w : unit Lwt.u;
  ctx : Cohttp_lwt_unix_net.ctx;
  thread : unit Lwt.t;
  exception_filter: Exception.exn_filter;
}

val start :
  Environment.t ->
  Config_t.config_listener ->
  Config_t.config_http_settings ->
  routing ->
  t Lwt.t

val stop : t -> unit Lwt.t

val close : t -> unit Lwt.t
