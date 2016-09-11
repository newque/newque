open Core.Std

type t

val of_header :
  ?sep:string ->
  mode:Mode.Pub.t ->
  msgs:Message.t list ->
  string option ->
  (t list, string) Result.t

val to_string : t -> string

val time_ns : unit -> int64

val uuid : unit -> string
