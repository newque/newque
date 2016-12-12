open Core.Std
open Cohttp

type splitter = (string -> string list)
val make_splitter : sep:string -> splitter
val split : sep:string -> string -> string list

val parse_int64 : string -> int64 option

val stream_map_array_s :
  batch_size:int ->
  mapper:('a array -> 'b array) ->
  'a array Lwt_stream.t ->
  'b Lwt_stream.t

val stream_to_string :
  buffer_size:int ->
  ?init:string option ->
  string Lwt_stream.t ->
  string Lwt.t

val stream_to_array :
  splitter:splitter ->
  ?init:string option ->
  string Lwt_stream.t ->
  string array Lwt.t

val zip_group : size:int -> 'a array -> 'b array -> ('a * 'b) array list Lwt.t

val array_to_list_rev_mapi : mapper:(int -> 'a -> 'b) -> 'a array -> 'b list

val parse_sync : ('a -> 'b) -> 'a -> ('b, string) Result.t

val header_name_to_int64_opt : Header.t -> string -> int64 option

val make_interval : float -> (unit -> 'a Lwt.t) -> unit -> 'b Lwt.t

val time_ns_int64 : unit -> int64
val time_ns_int63 : unit -> Int63.t
val time_ms_float : unit -> float
