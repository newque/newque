open Core.Std

type t = {
  table: Channel.t String.Table.t String.Table.t;
} [@@deriving sexp]

val create : unit -> t

val register_listeners : t -> Listener.t list -> (unit, string list) Result.t

val register_channels : t -> Channel.t list -> (unit, string list) Result.t

val write :
  t ->
  listen_name:string ->
  chan_name:string ->
  id_header:string option ->
  mode:Mode.Write.t ->
  string Lwt_stream.t ->
  (int, string list) Result.t Lwt.t

val read :
  t ->
  listen_name:string ->
  chan_name:string ->
  id_header:string option ->
  mode:Mode.Read.t ->
  (unit, string list) Result.t Lwt.t

val count :
  t ->
  listen_name:string ->
  chan_name:string ->
  mode:Mode.Count.t ->
  (int, string list) Result.t Lwt.t
