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
  | `Single -> [| Single (Single.of_string str) |]
  | `Multiple -> Array.of_list_map ~f:(fun s -> Single (Single.of_string s)) (split str)
  | `Atomic -> [| Atomic (Atomic.of_string_list (split str)) |]

let of_stream ~mode ~sep ~buffer_size stream =
  match mode with
  | `Single ->
    let%lwt s = Single.of_stream ~buffer_size stream in
    return [| Single s |]
  | `Multiple ->
    let%lwt arr = Single.array_of_stream ~sep stream in
    return (Array.map arr ~f:(fun s -> Single s))
  | `Atomic ->
    let%lwt arr = Single.array_of_stream ~sep stream in
    return [| Atomic (Atomic.of_singles arr) |]

let serialize msg =
  #ifdef DEBUG
    Util.string_of_sexp ~pretty:false (sexp_of_t msg)
    #else
  Protobuf.Encoder.encode_exn to_protobuf msg
    #endif

let parse_exn blob =
  #ifdef DEBUG
    t_of_sexp (Util.sexp_of_json_str_exn blob)
    #else
  Protobuf.Decoder.decode_exn from_protobuf blob
    #endif


let contents msg =
  match msg with
  | Single m -> [| Single.contents m |]
  | Atomic m -> Atomic.contents m
