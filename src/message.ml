open Core.Std
open Lwt

type t = {
  raw: string;
}

(* Called from the JSON parser *)
(* let separator_validation str =
   match String.length str with
   | 0 -> Some "Message separator cannot be empty"
   | x -> None *)

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
