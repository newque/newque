type t [@@deriving sexp]

val of_string :
  mode:Mode.Pub.t ->
  sep:string ->
  string ->
  [ `One of t | `Many of t list]

val of_stream :
  mode:Mode.Pub.t ->
  sep:string ->
  buffer_size:int ->
  string Lwt_stream.t ->
  [ `One of t | `Many of t list] Lwt.t

val serialize : t -> string
val parse : string -> t
