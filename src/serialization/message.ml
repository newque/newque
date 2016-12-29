open Core.Std
open Lwt

type t =
  | Multiple of string Collection.t
  | Atomic of string Collection.t

type flat =
  | F_single of string [@key 1]
  | F_atomic of string list [@key 2]
[@@deriving protobuf]

let of_string_coll ~atomic messages =
  begin match atomic with
    | false -> Multiple messages
    | true -> Atomic messages
  end

let of_string ~format ~mode ~splitter str =
  let open Http_format in
  match format with
  | Json ->
    let open Json_obj_j in
    begin match Util.parse_sync input_array_of_string str with
      | (Error _) as err -> err
      | Ok { atomic; messages } -> Ok (of_string_coll ~atomic (Collection.of_array messages))
    end
  | Plaintext ->
    let arr = begin match mode with
      | `Single -> Multiple (Collection.singleton str)
      | `Multiple -> of_string_coll ~atomic:false (Collection.of_list (splitter str))
      | `Atomic -> of_string_coll ~atomic:true (Collection.of_list (splitter str))
    end in
    Ok arr

let of_stream ~format ~mode ~splitter ~buffer_size stream =
  let open Http_format in
  match format with
  | Json ->
    let%lwt str = Util.stream_to_string ~buffer_size stream in
    begin match of_string ~format ~mode ~splitter str with
      | Error str -> failwith str
      | Ok messages -> return messages
    end
  | Plaintext ->
    begin match mode with
      | `Single ->
        let%lwt s = Util.stream_to_string ~buffer_size stream in
        return (Multiple (Collection.singleton s))
      | `Multiple ->
        let%lwt arr = Util.stream_to_collection ~splitter stream in
        return (Multiple arr)
      | `Atomic ->
        let%lwt arr = Util.stream_to_collection ~splitter stream in
        return (Atomic arr)
    end

let serialize_full msg =
  let serialize = Protobuf.Encoder.encode_exn flat_to_protobuf in
  match msg with
  | Multiple m ->
    Collection.to_coll_map m ~f:(fun x -> serialize (F_single x))
  | Atomic m ->
    let ll = Collection.to_list m |> snd in
    Collection.singleton (serialize (F_atomic ll))

let serialize_raw msg =
  match msg with
  | Multiple m -> m
  | Atomic m -> m

let parse_full_exn blob =
  try
    match Protobuf.Decoder.decode_exn flat_from_protobuf blob with
    | F_single s -> [s]
    | F_atomic m -> m
  with
  | Protobuf.Decoder.Failure err ->
    let str = Protobuf.Decoder.error_to_string err in
    failwith (sprintf "Unable to parse the wrapped messages, did it get corrupted? Reason: %s" str)

let length ~raw msg =
  match msg with
  | Multiple m -> Collection.length m
  | Atomic m when raw -> Collection.length m
  | Atomic _ -> 1
