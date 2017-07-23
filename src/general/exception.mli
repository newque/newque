type exn_filter = (exn -> string list * bool)

exception Multiple_public_exn of string list
exception Public_exn of string
exception Upstream_error of string

val human : exn -> string

val human_list : exn -> string list

val human_bt : exn -> string * string

val full : exn -> string

val default_error : string

val is_public : exn -> bool

val create_exception_filter :
  section:string ->
  main_env:Environment.t ->
  listener_env:Environment.t option ->
  exn_filter
