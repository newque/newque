open Core.Std

type t = string

val uuid : unit -> string

val default_separator : string

val array_random : int -> t array

val array_of_string_opt :
  ?sep:string ->
  mode:Mode.Write.t ->
  length_none:int ->
  string option ->
  (t array, string) Result.t

