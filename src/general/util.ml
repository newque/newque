open Core.Std
open Lwt
open Cohttp

type splitter = (string -> string list) [@@deriving sexp]
let make_splitter ~sep =
  let delim = Str.regexp_string sep in
  Str.split_delim delim

let parse_int64 str =
  try Some (Int64.of_string str)
  with _ -> None

(* An efficient lazy stream flattener *)
let coll_stream_flatten_map_s ~batch_size ~mapper coll_stream =
  let capacity = Int.min batch_size 100000 in (* Sanity check... *)
  let queue = Queue.create ~capacity () in
  Lwt_stream.from (fun () ->
    match Queue.dequeue queue with
    | (Some _) as x -> return x
    | None ->
      begin match%lwt Lwt_stream.get coll_stream with
        | Some coll ->
          let mapped = mapper coll in
          (* Optimization for the common 1 and 0 cases *)
          begin match Collection.length mapped with
            | 1 -> return (Collection.first mapped)
            | 0 -> return_none
            | _ ->
              Collection.add_to_queue mapped queue;
              return (Queue.dequeue queue)
          end
        | None -> return_none
      end
  )

let stream_to_string ~buffer_size ?init stream =
  let buffer = Bigbuffer.create buffer_size in
  Option.iter init ~f:(Bigbuffer.add_string buffer);
  let%lwt () = Lwt_stream.iter_s
      (fun chunk -> Bigbuffer.add_string buffer chunk; return_unit)
      stream
  in
  return (Bigbuffer.contents buffer)

let stream_to_collection ~splitter ?(init=(Some "")) stream =
  let queue = Queue.create () in
  let%lwt last = Lwt_stream.fold_s (fun read leftover ->
      let chunk = Option.value_map leftover ~default:read ~f:(fun left -> sprintf "%s%s" left read) in
      let lines = splitter chunk in
      let (fulls, partial) = List.split_n lines ((List.length lines) - 1) in
      Queue.enqueue_all queue fulls;
      return (List.hd partial)
    ) stream init
  in
  Option.iter last ~f:(fun raw -> Queue.enqueue queue raw);
  return (Collection.of_queue queue)

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
