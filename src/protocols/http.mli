open Core.Std
open Sexplib.Conv

type t = {
  generic : Config_t.config_listener;
  specific : Config_t.config_http_settings;
  sock : Lwt_unix.file_descr;
  mutable filter :
    Cohttp_lwt_unix.Server.conn ->
    Cohttp_lwt_unix.Request.t ->
    Cohttp_lwt_body.t ->
    (string * Mode.t, int * string list) Result.t Lwt.t;
  close : unit Lwt.u;
  ctx : Cohttp_lwt_unix_net.ctx;
  thread : unit Lwt.t;
} [@@deriving sexp_of]

val start :
  Config_t.config_listener ->
  Config_t.config_http_settings ->
  (
    chan_name:string ->
    mode:Mode.Pub.t ->
    string Lwt_stream.t ->
    (int, int * string list) Result.t Lwt.t
  ) ->
  t Lwt.t

val stop : t ->
  unit Lwt.t

val close : t -> unit Lwt.t
