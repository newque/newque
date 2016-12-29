open Core.Std

type admin_routing = {
  listeners_by_port: int option -> Yojson.Basic.json;
  channels_by_name: string option -> Yojson.Basic.json Lwt.t;
}

(* Routing Return value type *)

type standard_routing = {
  write_http: (
    chan_name:string ->
    id_header:string option ->
    mode:Mode.Write.t ->
    string Lwt_stream.t ->
    (int option, string list) Result.t Lwt.t);
  write_zmq: (
    chan_name:string ->
    ids:string Collection.t ->
    msgs:string Collection.t ->
    atomic:bool ->
    (int option, string list) Result.t Lwt.t);
  read_slice: (
    chan_name:string ->
    mode:Mode.Read.t ->
    limit:int64 option ->
    (Persistence.slice * Channel.t, string list) Result.t Lwt.t);
  read_stream: (
    chan_name:string ->
    mode:Mode.Read.t ->
    (string Lwt_stream.t * Channel.t, string list) Result.t Lwt.t);
  count: (
    chan_name:string ->
    mode:Mode.Count.t ->
    (int64, string list) Result.t Lwt.t);
  delete: (
    chan_name:string ->
    mode:Mode.Delete.t ->
    (unit, string list) Result.t Lwt.t);
  health: (
    chan_name:string option ->
    mode:Mode.Health.t ->
    string list Lwt.t);
}

type routing =
  | Admin of admin_routing
  | Standard of standard_routing
