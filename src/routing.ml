open Core.Std

type admin_routing = {
  (* Channels (accessed by name) by listener.id *)
  table: Channel.t String.Table.t String.Table.t;
}

type standard_routing = {
  push: (
    chan_name:string ->
    id_header:string option ->
    mode:Mode.Write.t ->
    string Lwt_stream.t ->
    (int option, string list) Result.t Lwt.t);
  read_slice: (
    chan_name:string ->
    mode:Mode.Read.t ->
    limit:int64 ->
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
