open Core

type t = {
  table: Channel.t String.Table.t String.Table.t;
}

val create : unit -> t

val register_listeners : t -> Listener.t list -> (unit, string list) Result.t
val register_channels : t -> Channel.t list -> (unit, string list) Result.t

val find_chan : t -> listen_name:string -> chan_name:string -> (Channel.t, string) Result.t
val all_channels : t -> (string * Channel.t) list Lwt.t

val write_shared :
  t ->
  listen_name:string ->
  chan:Channel.t ->
  write:Write_settings.t ->
  msgs:Message.t ->
  ids:Id.t Collection.t ->
  (int option, string list) Result.t Lwt.t

val write_http :
  t ->
  listen_name:string ->
  chan_name:string ->
  id_header:string option ->
  mode:Mode.Write.t ->
  string Lwt_stream.t ->
  (int option, string list) Result.t Lwt.t

val write_zmq :
  t ->
  listen_name:string ->
  chan_name:string ->
  ids:string Collection.t ->
  msgs:string Collection.t ->
  atomic:bool ->
  (int option, string list) Result.t Lwt.t

val read_slice :
  t ->
  listen_name:string ->
  chan_name:string ->
  mode:Mode.Read.t ->
  limit:int64 option ->
  (Persistence.slice * Channel.t, string list) Result.t Lwt.t

val read_stream :
  t ->
  listen_name:string ->
  chan_name:string ->
  mode:Mode.Read.t ->
  limit:int64 option ->
  (string Lwt_stream.t * Channel.t, string list) Result.t Lwt.t

val count :
  t ->
  listen_name:string ->
  chan_name:string ->
  mode:Mode.Count.t ->
  (int64, string list) Result.t Lwt.t

val delete :
  t ->
  listen_name:string ->
  chan_name:string ->
  mode:Mode.Delete.t ->
  (unit, string list) Result.t Lwt.t

val health :
  t ->
  listen_name:string ->
  chan_name:(string option) ->
  mode:Mode.Health.t ->
  string list Lwt.t
