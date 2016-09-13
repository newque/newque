open Core.Std

type t

val rev_list_of_header :
  ?sep:string ->
  mode:Mode.Write.t ->
  msgs:Message.t list ->
  string option ->
  (t list, string) Result.t

val to_string : t -> string

val time_ns : unit -> int64

val uuid : unit -> string
