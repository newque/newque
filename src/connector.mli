open Core.Std

type 'a t [@@deriving sexp]

val create : float -> 'a t

val submit : 'a t -> string -> 'a Lwt.t

val resolve : 'a t -> string -> 'a -> unit Lwt.t
