open Core.Std
open Cohttp
open Cohttp_lwt_unix

type t = {
  generic : Config_t.config_listener;
  specific : Config_t.config_http_settings;
  sock : Lwt_unix.file_descr;
  close : unit Lwt.u;
  ctx : Cohttp_lwt_unix_net.ctx;
  thread : unit Lwt.t;
} [@@deriving sexp_of]

(* TODO: Clean this up.. *)
type standard_routing = {
  write: (
    chan_name:string ->
    id_header:string option ->
    mode:Mode.Write.t ->
    string Lwt_stream.t ->
    (int, string list) Result.t Lwt.t);
  read: (
    chan_name:string ->
    id_header:string option ->
    mode:Mode.Read.t ->
    (string array * string, string list) Result.t Lwt.t);
  count: (
    chan_name:string ->
    mode:Mode.Count.t ->
    (int64, string list) Result.t Lwt.t);
}

type http_routing =
  | Admin
  | Standard of standard_routing

val start :
  Config_t.config_listener ->
  Config_t.config_http_settings ->
  http_routing ->
  t Lwt.t

val stop : t -> unit Lwt.t

val close : t -> unit Lwt.t
