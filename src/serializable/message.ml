open Core.Std
open Lwt

type t =
  | Single of Single.t [@key 1]
  | Atomic of Atomic.t [@key 2]
[@@deriving protobuf, sexp]

let of_string ~mode ~sep str =
  let split str =
    let delim = Str.regexp_string sep in
    Str.split_delim delim str
  in
  match mode with
  | `Single -> `One (Single (Single.of_string str))
  | `Multiple -> `Many (List.map ~f:(fun s -> Single (Single.of_string s)) (split str))
  | `Atomic -> `One (Atomic (Atomic.of_strings (split str)))


let of_stream ~mode ~sep ~buffer_size stream =
  match mode with
  | `Single ->
    let%lwt s = Single.of_stream ~buffer_size stream in
    return (`One (Single s))
  | `Multiple ->
    let%lwt ll = Single.list_of_stream ~sep stream in
    return (`Many (List.map ll ~f:(fun s -> Single s)))
  | `Atomic ->
    let%lwt ll = Single.list_of_stream ~sep stream in
    return (`One ( Atomic (Atomic.of_singles ll)))

let serialize msg = Protobuf.Encoder.encode_exn to_protobuf msg
let parse blob : t = Protobuf.Decoder.decode_exn from_protobuf blob
