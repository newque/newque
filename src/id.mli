open Core.Std

type t

val default_separator : string

val array_of_string_opt :
  ?sep:string ->
  mode:Mode.Write.t ->
  msgs:Message.t array ->
  string option ->
  (t array, string) Result.t

val to_string : t -> string
val of_string : string -> t

val uuid : unit -> string
