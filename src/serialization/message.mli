type t [@@deriving sexp]

val of_string_list :
  atomic:bool ->
  string list ->
  t array

val of_string :
  format:Io_format.t ->
  mode:Mode.Write.t ->
  sep:string ->
  string ->
  t array

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
