type t [@@deriving sexp]

val create : string -> t Lwt.t

val insert : t -> string list -> int Lwt.t
