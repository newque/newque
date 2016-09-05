type t [@@deriving protobuf, sexp]

val of_singles : Single.t list -> t

val of_strings : string list -> t
