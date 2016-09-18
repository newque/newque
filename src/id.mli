open Core.Std

type t

val array_of_header :
  ?sep:string ->
  mode:Mode.Write.t ->
  msgs:Message.t array ->
  string option ->
  (t array, string) Result.t

val to_string : t -> string

val time_ns : unit -> int64

val uuid : unit -> string
