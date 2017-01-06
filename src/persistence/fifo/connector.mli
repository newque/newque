open Core.Std

exception Upstream_error of string

type 'a t

val create : float -> 'a t

(* Returns a thunk. The timer starts after the thunk is executed. *)
val submit : 'a t -> string -> string -> (unit -> 'a Lwt.t)

val resolve : 'a t -> string -> 'a -> unit Lwt.t
