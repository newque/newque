open Core.Std

type t [@@deriving sexp]

val of_string_array :
  atomic:bool ->
  string array ->
  t array

val of_string :
  format:Io_format.t ->
  mode:Mode.Write.t ->
  sep:string ->
  string ->
  ((t array), string) Result.t

val of_stream :
  format:Io_format.t ->
  mode:Mode.Write.t ->
  sep:string ->
  buffer_size:int ->
  string Lwt_stream.t ->
  t array Lwt.t

val serialize : t -> string

val parse_exn : string -> t

val contents : t -> string array
