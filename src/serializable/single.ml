open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Single" end)

type t = {
  raw: string [@key 1];
} [@@deriving protobuf, sexp]

let of_stream ~buffer_size ?(init=(Some "")) stream =
  let buffer = Bigbuffer.create buffer_size in
  Option.iter init ~f:(Bigbuffer.add_string buffer);
  let%lwt () = Lwt_stream.iter_s
      (fun chunk -> Bigbuffer.add_string buffer chunk; return_unit)
      stream
  in
  let raw = Bigbuffer.contents buffer in
  return {raw}

let of_string raw = {raw}

let contents single = single.raw

let array_of_stream ~sep ?(init=(Some "")) stream =
  let%lwt (msgs, last) = Lwt_stream.fold_s (fun read (acc, leftover) ->
      let chunk = Option.value_map leftover ~default:read ~f:(fun a -> a ^ read) in
      Util.split ~sep chunk
      |> (fun lines -> List.split_n lines (List.length lines))
      |> (fun (fulls, partial) ->
          (List.rev_map_append fulls acc ~f:(fun raw -> {raw})), List.hd partial)
      |> return
    ) stream ([], init)
  in
  return (Array.of_list_rev (Option.value_map last ~default:msgs ~f:(fun raw -> {raw}::msgs)))
