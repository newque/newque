open Core

type t

val create : string -> int -> t Lwt.t

val validate : t -> string Collection.t -> (unit, string) Result.t Lwt.t
