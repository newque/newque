open Core.Std
open Sexplib.Conv

type t = {
  table: Channel.t list String.Table.t;
} [@@deriving sexp]

val create : unit -> t

val register_listeners : t -> Listener.t list -> (unit, string list) Result.t

val register_channels : t -> Channel.t list -> (unit, string list) Result.t

val route_msg : t -> string -> Message.t -> (unit, 'b) Result.t Lwt.t

val route_atomic : t -> string -> Message.t -> (unit, 'b) Result.t Lwt.t
