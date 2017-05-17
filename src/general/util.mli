open Core
open Cohttp

type splitter = (string -> string list)
val make_splitter : sep:string -> splitter

val parse_int64 : string -> int64 option

val coll_stream_flatten_map_s :
  batch_size:int ->
  mapper:('a Collection.t -> 'b Collection.t) ->
  'a Collection.t Lwt_stream.t ->
  'b Lwt_stream.t

val stream_to_string :
  buffer_size:int ->
  ?init:string ->
  string Lwt_stream.t ->
  string Lwt.t

val stream_to_collection :
  splitter:splitter ->
  ?init:string option ->
  string Lwt_stream.t ->
  string Collection.t Lwt.t

val parse_sync : ('a -> 'b) -> 'a -> ('b, string) Result.t

val header_name_to_int64_opt : Header.t -> string -> int64 option

val make_interval : float -> (unit -> 'a Lwt.t) -> unit -> 'b Lwt.t

val time_ns_int63 : unit -> Int63.t
val time_ns_int64 : unit -> int64
val time_ms_float : unit -> float
