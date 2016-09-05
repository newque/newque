open Sexplib.Conv

type t [@@deriving sexp]

val create : tablenames:string list -> string -> t
