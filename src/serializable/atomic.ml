open Core.Std

type t = {
  msgs: Single.t list [@key 1];
} [@@deriving protobuf]

let of_singles msgs = {msgs}
let of_strings strs = {msgs = List.map ~f:Single.of_string strs}
