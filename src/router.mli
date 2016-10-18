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
  (int option, string list) Result.t Lwt.t

val read_slice :
  t ->
  listen_name:string ->
  chan_name:string ->
  id_header:string option ->
  mode:Mode.Read.t ->
  (string array * string, string list) Result.t Lwt.t

val read_stream :
  t ->
  listen_name:string ->
  chan_name:string ->
  id_header:string option ->
  mode:Mode.Read.t ->
  (string Lwt_stream.t * string, string list) Result.t Lwt.t

val count :
  t ->
  listen_name:string ->
  chan_name:string ->
  mode:Mode.Count.t ->
  (int64, string list) Result.t Lwt.t
