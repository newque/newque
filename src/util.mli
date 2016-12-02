open Core.Std
open Cohttp

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
  sep:string ->
  ?init:string option ->
  string Lwt_stream.t ->
  string array Lwt.t

val zip_group : size:int -> 'a array -> 'b array -> ('a * 'b) array list Lwt.t

val array_to_list_rev_mapi : mapper:(int -> 'a -> 'b) -> 'a array -> 'b list

val json_of_sexp : Sexp.t -> Yojson.Basic.json
val string_of_sexp : ?pretty:bool -> Sexp.t -> string

val sexp_of_json_exn : Yojson.Basic.json -> Sexp.t
val sexp_of_json_str_exn : string -> Sexp.t

val sexp_of_atdgen_exn : string -> Sexp.t

val parse_sync : ('a -> 'b) -> 'a -> ('b, string) Result.t
val parse_async : ('a -> 'b) -> 'a -> 'b Lwt.t
val parse_async_bind : ('a -> 'b Lwt.t) -> 'a -> 'b Lwt.t

val header_name_to_int64_opt : Header.t -> string -> int64 option

val make_interval : float -> (unit -> 'a Lwt.t) -> unit -> 'b Lwt.t

val time_ns_int64 : unit -> int64
val time_ns_int63 : unit -> Int63.t
val time_ms_float : unit -> float

val append_to_path : Uri.t -> string -> Uri.t
