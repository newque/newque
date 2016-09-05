type t [@@deriving protobuf]

val of_stream :
  buffer_size:int ->
  ?init:string option ->
  string Lwt_stream.t ->
  t Lwt.t

val of_string : string -> t

val list_of_stream :
  sep:string ->
  ?init:string option ->
  string Lwt_stream.t ->
  t list Lwt.t
