open Core.Std
open Sexplib.Conv

type t = {
  table: Channel.t String.Table.t String.Table.t;
} [@@deriving sexp]

val create : unit -> t

val register_listeners : t -> Listener.t list -> (unit, string list) Result.t

val register_channels : t -> Channel.t list -> (unit, string list) Result.t

val route :
  t ->
  listen_name:string ->
  chan_name:string ->
  mode:Mode.t ->
  string Lwt_stream.t ->
  (int, string) Result.t Lwt.t
