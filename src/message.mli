type t

val list_of_stream :
  sep:string ->
  ?init:string option ->
  string Lwt_stream.t ->
  t list Lwt.t
