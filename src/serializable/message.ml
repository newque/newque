open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Message" end)

type t =
  | Single of Single.t [@key 1]
  | Atomic of Atomic.t [@key 2]
[@@deriving protobuf, sexp]

let of_string ~mode ~sep str =
  let split = Util.split ~sep in
  match mode with
  | `Single -> [Single (Single.of_string str)]
  | `Multiple -> List.map ~f:(fun s -> Single (Single.of_string s)) (split str)
  | `Atomic -> [Atomic (Atomic.of_strings (split str))]

let of_stream ~mode ~sep ~buffer_size stream =
  match mode with
  | `Single ->
    let%lwt s = Single.of_stream ~buffer_size stream in
    return [Single s]
  | `Multiple ->
    let%lwt ll = Single.rev_list_of_stream ~sep stream in
    return (List.map ll ~f:(fun s -> Single s))
  | `Atomic ->
    let%lwt ll = Single.rev_list_of_stream ~sep stream in
    return [Atomic (Atomic.of_singles ll)]

let serialize msg = Protobuf.Encoder.encode_exn to_protobuf msg
let parse blob : t = Protobuf.Decoder.decode_exn from_protobuf blob
