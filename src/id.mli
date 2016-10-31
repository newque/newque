open Core.Std

type t

val array_of_string_opt :
  ?sep:string ->
  mode:Mode.Write.t ->
  msgs:Message.t array ->
  string option ->
  (t array, string) Result.t

val to_string : t -> string
val of_string : string -> t

val time_ns : unit -> int64

val uuid : unit -> string
