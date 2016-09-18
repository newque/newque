type t [@@deriving protobuf, sexp]

val of_singles : Single.t array -> t

val of_strings : string array -> t

val contents : t -> string array
