type t [@@deriving protobuf, sexp]

val of_stream :
  buffer_size:int ->
  ?init:string option ->
  string Lwt_stream.t ->
  t Lwt.t

val of_string : string -> t

val contents : t -> string

val array_of_stream :
  sep:string ->
  ?init:string option ->
  string Lwt_stream.t ->
  t array Lwt.t
