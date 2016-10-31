open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Message" end)

type t =
  | Single of Single.t [@key 1]
  | Atomic of Atomic.t [@key 2]
[@@deriving protobuf, sexp]

let of_string_list ~atomic messages =
  begin match atomic with
    | false ->
      Array.of_list_map ~f:(fun raw -> Single (Single.of_string raw)) messages
    | true ->
      [| Atomic (Atomic.of_string_list messages) |]
  end

let of_string ~format ~mode ~sep str =
  let open Io_format in
  match format with
  | Json ->
    let open Config_j in
    let { atomic; messages } = input_message_of_string str in
    of_string_list ~atomic messages
  | Plaintext ->
    let split = Util.split ~sep in
    begin match mode with
      | `Single -> [| Single (Single.of_string str) |]
      | `Multiple -> of_string_list ~atomic:false (split str)
      | `Atomic -> of_string_list ~atomic:true (split str)
    end

let of_stream ~format ~mode ~sep ~buffer_size stream =
  let open Io_format in
  match format with
  | Json ->
    let%lwt str = Util.stream_to_string ~buffer_size stream in
    return (of_string ~format ~mode ~sep str)
  | Plaintext ->
    begin match mode with
      | `Single ->
        let%lwt s = Single.of_stream ~buffer_size stream in
        return [| Single s |]
      | `Multiple ->
        Util.stream_to_array ~mapper:(fun raw -> Single (Single.of_string raw)) ~sep stream
      | `Atomic ->
        let%lwt arr = Single.array_of_stream ~sep stream in
        return [| Atomic (Atomic.of_singles arr) |]
    end

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
