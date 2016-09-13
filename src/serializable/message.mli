type t [@@deriving sexp]

val of_string :
  mode:Mode.Write.t ->
  sep:string ->
  string ->
  t list

val of_stream :
  mode:Mode.Write.t ->
  sep:string ->
  buffer_size:int ->
  string Lwt_stream.t ->
  t list Lwt.t

val serialize : t -> string

val parse : string -> t
