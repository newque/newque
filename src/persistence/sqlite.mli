open Core.Std

type t [@@deriving sexp]

val create : string -> avg_read:int -> t Lwt.t

val close : t -> unit Lwt.t

val push : t -> msgs:string array -> ids:string array -> int Lwt.t

(* See comments in Persistence *)
val pull :
  t ->
  search:Search.t ->
  fetch_last:bool ->
  (string array * int64 option * (string * int64) option) Lwt.t

val size : t -> int64 Lwt.t

val delete : t -> unit Lwt.t

val health : t -> string list Lwt.t
