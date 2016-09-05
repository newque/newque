type t [@@deriving protobuf]

val of_singles : Single.t list -> t

val of_strings : string list -> t
