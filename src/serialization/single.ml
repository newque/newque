open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Single" end)

type t = {
  raw: string [@key 1];
} [@@deriving protobuf, sexp]

let of_stream ~buffer_size ?init stream =
  let%lwt raw = Util.stream_to_string ~buffer_size ?init stream in
  return {raw}

let of_string raw = {raw}

let contents single = single.raw

let array_of_stream ~sep ?init stream =
  Util.stream_to_array ~mapper:of_string ~sep ?init stream
