open Core.Std

type t = {
  msgs: Single.t array [@key 1];
} [@@deriving protobuf, sexp]

let of_singles msgs = {msgs}

let of_string_array strs = {msgs = Array.map ~f:Single.of_string strs}

let contents atomic = Array.map atomic.msgs ~f:Single.contents
