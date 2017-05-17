open Core

type t

val of_string_coll :
  atomic:bool ->
  string Collection.t ->
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

val serialize_full : t -> string Collection.t
val serialize_raw : t -> string Collection.t

val parse_full_exn : string -> string list

val length : raw:bool -> t -> int

val swap_contents : t -> string Collection.t -> t
