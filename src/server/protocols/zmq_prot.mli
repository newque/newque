open Core.Std
open Routing

type worker = {
  accept: unit Lwt.t;
  socket: [`Dealer] Lwt_zmq.Socket.t;
}

type t = {
  generic : Config_t.config_listener;
  specific : Config_t.config_zmq_settings;
  inproc: string;
  inbound: string;
  frontend: [`Router] ZMQ.Socket.t;
  backend: [`Dealer] ZMQ.Socket.t;
  workers: worker array;
  proxy: unit Lwt.t;
  stop_w: unit Lwt.u;
}

val start :
  Config_t.config_listener ->
  Config_t.config_zmq_settings ->
  routing ->
  t Lwt.t

val stop : t -> unit Lwt.t

val close : t -> unit Lwt.t
