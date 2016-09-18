type t [@@deriving protobuf, sexp]

val of_singles : Single.t array -> t

val of_string_list : string list -> t

val contents : t -> string array
