type t

val of_stream :
  buffer_size:int ->
  ?init:string option ->
  string Lwt_stream.t ->
  t Lwt.t

val list_of_stream :
  sep:string ->
  ?init:string option ->
  string Lwt_stream.t ->
  t list Lwt.t

val contents : t -> string

val length : t -> int
