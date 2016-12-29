open Core.Std

type t = string

val uuid : unit -> string
val uuid_bytes : unit -> string

val default_separator : string

val coll_random : int -> t Collection.t

val coll_of_string_opt :
  ?sep:string ->
  mode:Mode.Write.t ->
  length_none:int ->
  string option ->
  (t Collection.t, string) Result.t
