open Core.Std

val split : sep:string -> string -> string list

val parse_int64 : string -> int64 option

val stream_map_array_s: batch_size:int -> mapper:('a array -> 'b array) -> 'a array Lwt_stream.t -> 'b Lwt_stream.t

val zip_group : size:int -> 'a array -> 'b array -> ('a * 'b) array list Lwt.t

val json_of_sexp : Sexp.t -> Yojson.Basic.json
val string_of_sexp : ?pretty:bool -> Sexp.t -> string

val sexp_of_json_exn : Yojson.Basic.json -> Sexp.t
val sexp_of_json_str_exn : string -> Sexp.t

val sexp_of_atdgen : string -> Sexp.t
