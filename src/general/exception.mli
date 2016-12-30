exception Multiple_exn of string list

val human : exn -> string

val human_list : exn -> string list

val human_bt : exn -> string * string

val full : exn -> string
