open Core.Std

type t [@@deriving sexp]

val of_string_array :
  atomic:bool ->
  string array ->
  t

val of_string :
  format:Http_format.t ->
  mode:Mode.Write.t ->
  splitter:Util.splitter ->
  string ->
  (t, string) Result.t

val of_stream :
  format:Http_format.t ->
  mode:Mode.Write.t ->
  splitter:Util.splitter ->
  buffer_size:int ->
  string Lwt_stream.t ->
  t Lwt.t

val serialize_full : t -> string array
val serialize_raw : t -> string array

val parse_full_exn : string -> string array

val length : raw:bool -> t -> int
