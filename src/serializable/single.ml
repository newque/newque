open Core.Std
open Lwt

type t = {
  raw: string [@key 1];
} [@@deriving protobuf]

let of_stream ~buffer_size ?(init=None) stream =
  let buffer = Bigbuffer.create buffer_size in
  Option.iter init ~f:(Bigbuffer.add_string buffer);
  let%lwt () = Lwt_stream.iter_s
      (fun chunk -> Bigbuffer.add_string buffer chunk; return_unit)
      stream
  in
  return {raw=(Bigbuffer.contents buffer);}

let of_string raw = {raw}

let list_of_stream ~sep ?(init=None) stream =
  let delim = Str.regexp_string sep in
  let%lwt (msgs, last) = Lwt_stream.fold_s (fun read (acc, leftover) ->
      let chunk = Option.value_map leftover ~default:read ~f:(fun a -> a ^ read) in
      Str.split_delim delim chunk
      |> (fun lines -> List.split_n lines (List.length lines))
      |> (fun (full, part) ->
          (List.rev_map_append full acc ~f:(fun raw -> {raw})), List.hd part)
      |> return
    ) stream ([], init)
  in
  Option.value_map last ~default:msgs ~f:(fun raw -> {raw}::msgs)
  |> return
