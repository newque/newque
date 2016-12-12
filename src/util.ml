open Core.Std
open Lwt
open Cohttp

type splitter = (string -> string list)
let make_splitter ~sep =
  let delim = Str.regexp_string sep in
  Str.split_delim delim

let split ~sep str =
  let delim = Str.regexp_string sep in
  Str.split_delim delim str

let parse_int64 str =
  try Some (Int64.of_string str)
  with _ -> None

(* This was rewritten in c/fortran style for efficiency *)
let zip_group ~size arr1 arr2 =
  if Array.length arr1 <> Array.length arr2 then
    fail_with (sprintf "Different array lengths: %d and %d" (Array.length arr1) (Array.length arr2))
  else
  let len = Array.length arr1 in
  let div = len / size in
  let groups = if div * size = len then div else div + 1 in
  return (
    List.init groups ~f:(fun i ->
      Array.init (Int.min size (len - (i * size))) ~f:(fun j ->
        (arr1.((i * size) + j), arr2.((i * size) + j))
      )
    )
  )

let array_to_list_rev_mapi ~mapper arr =
  Array.foldi arr ~init:[] ~f:(fun i acc elt ->
    (mapper i elt)::acc
  )

(* An efficient lazy stream flattener *)
let stream_map_array_s ~batch_size ~mapper arr_stream =
  let capacity = Int.min batch_size 10000 in (* Sanity check... *)
  let queue = Queue.create ~capacity () in
  Lwt_stream.from (fun () ->
    match Queue.dequeue queue with
    | (Some _) as x -> return x
    | None ->
      begin match%lwt Lwt_stream.get arr_stream with
        | Some arr ->
          Array.iter (mapper arr) ~f:(Queue.enqueue queue);
          return (Queue.dequeue queue)
        | None -> return_none
      end
  )

let stream_to_string ~buffer_size ?(init=(Some "")) stream =
  let buffer = Bigbuffer.create buffer_size in
  Option.iter init ~f:(Bigbuffer.add_string buffer);
  let%lwt () = Lwt_stream.iter_s
      (fun chunk -> Bigbuffer.add_string buffer chunk; return_unit)
      stream
  in
  return (Bigbuffer.contents buffer)

let stream_to_array ~splitter ?(init=(Some "")) stream =
  let queue = Queue.create () in
  let%lwt (msgs, last) = Lwt_stream.fold_s (fun read ((), leftover) ->
      let chunk = Option.value_map leftover ~default:read ~f:(fun a -> sprintf "%s%s" a read) in
      let lines = splitter chunk in
      let (fulls, partial) = List.split_n lines (List.length lines) in
      List.iter fulls ~f:(fun raw -> Queue.enqueue queue raw);
      return ((), List.hd partial)
    ) stream ((), init)
  in
  Option.iter last ~f:(fun raw -> Queue.enqueue queue raw);
  return (Queue.to_array queue)

let parse_sync parser str =
  try
    Ok (parser str)
  with
  | ex -> Error (Exception.human ex)

let header_name_to_int64_opt headers name =
  Option.bind
    (Header.get headers name)
    parse_int64

let rec make_interval every callback () =
  let%lwt () = Lwt_unix.sleep every in
  ignore_result (callback ());
  make_interval every callback ()

let time_ns_int64 () = Int63.to_int64 (Time_ns.to_int63_ns_since_epoch (Time_ns.now ()))
let time_ns_int63 () = Time_ns.to_int63_ns_since_epoch (Time_ns.now ())
let time_ms_float () = Time.to_float (Time.now ()) *. 1000.
