open Core.Std
open Lwt
open Cohttp

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

let stream_to_array ~sep ?(init=(Some "")) stream =
  let queue = Queue.create () in
  let split = split ~sep in
  let%lwt (msgs, last) = Lwt_stream.fold_s (fun read ((), leftover) ->
      let chunk = Option.value_map leftover ~default:read ~f:(fun a -> sprintf "%s%s" a read) in
      let lines = split chunk in
      let (fulls, partial) = List.split_n lines (List.length lines) in
      List.iter fulls ~f:(fun raw -> Queue.enqueue queue raw);
      return ((), List.hd partial)
    ) stream ((), init)
  in
  Option.iter last ~f:(fun raw -> Queue.enqueue queue raw);
  return (Queue.to_array queue)

let rec is_assoc sexp =
  match sexp with
  | [] -> true
  | (Sexp.Atom _)::_::tail -> is_assoc tail
  | _ -> false
let has_dup_keys ll =
  List.contains_dup (List.filteri ll ~f:(fun i sexp -> Int.(=) (i mod 2) 0))
let rec json_of_sexp sexp =
  match sexp with
  | Sexp.List ll when (is_assoc ll) && not (has_dup_keys ll) ->
    `Assoc (List.map (List.groupi ll ~break:(fun i _ _ -> i mod 2 = 0)) ~f:(function
        | [Sexp.Atom k; v] -> (k, (json_of_sexp v))
        | _ -> failwith "Unreachable"
      ))
  | Sexp.List ll -> `List (List.map ~f:json_of_sexp ll)
  | Sexp.Atom s when (String.lowercase s) = "true" -> `Bool true
  | Sexp.Atom s when (String.lowercase s) = "false" -> `Bool false
  | Sexp.Atom s when (String.lowercase s) = "null" -> `Null
  | Sexp.Atom x ->
    try
      let f = Float.of_string x in
      let i = Float.to_int f in
      if (Int.to_float i) = f then `Int i else `Float f
    with _ -> `String x

let string_of_sexp ?(pretty=true) sexp =
  if pretty then Yojson.Basic.pretty_to_string (json_of_sexp sexp)
  else Yojson.Basic.to_string (json_of_sexp sexp)

let rec sexp_of_json_exn json =
  match json with
  | `Assoc ll ->
    Sexp.List (List.concat_map ll ~f:(fun (key, json) ->
        [Sexp.Atom key; sexp_of_json_exn json]
      ))
  | `Bool b -> Sexp.Atom (Bool.to_string b)
  | `Float f -> Sexp.Atom (Float.to_string f)
  | `Int i -> Sexp.Atom (Int.to_string i)
  | `List ll -> Sexp.List (List.map ll ~f:sexp_of_json_exn)
  | `Null -> Sexp.Atom "null"
  | `String s -> Sexp.Atom s

let sexp_of_json_str_exn str =
  let json = Yojson.Basic.from_string str in
  sexp_of_json_exn json

let sexp_of_atdgen_exn str =
  match Yojson.Basic.from_string str with
  | `String s -> Sexp.Atom s
  | _ -> Sexp.Atom str

let json_error_regexp = Str.regexp "[ \\\n]"
let parse_sync parser str =
  try
    Ok (parser str)
  with
  | Unix.Unix_error (c, n, p) -> Error (Fs.format_unix_exn c n p)
  | Ag_oj_run.Error str
  | Yojson.Json_error str ->
    let replaced = Str.global_replace json_error_regexp " " str in
    Error replaced

let parse_async parser str =
  try
    return (parser str)
  with
  | Unix.Unix_error (c, n, p) -> fail_with (Fs.format_unix_exn c n p)
  | Ag_oj_run.Error str
  | Yojson.Json_error str ->
    let replaced = Str.global_replace json_error_regexp " " str in
    fail_with replaced

let parse_async_bind parser str =
  try
    parser str
  with
  | Unix.Unix_error (c, n, p) -> fail_with (Fs.format_unix_exn c n p)
  | Ag_oj_run.Error str
  | Yojson.Json_error str ->
    let replaced = Str.global_replace json_error_regexp " " str in
    fail_with replaced

let header_name_to_int64_opt headers name =
  Option.bind
    (Header.get headers name)
    (fun x -> Option.try_with (fun () -> Int64.of_string x))

let rec make_interval every callback () =
  let%lwt () = Lwt_unix.sleep every in
  ignore_result (callback ());
  make_interval every callback ()

let time_ns_int64 () = Int63.to_int64 (Time_ns.to_int63_ns_since_epoch (Time_ns.now ()))
let time_ns_int63 () = Time_ns.to_int63_ns_since_epoch (Time_ns.now ())
let time_ms_float () = Time.to_float (Time.now ()) *. 1000.

let append_to_path uri append =
  let base_path = Uri.path uri in
  if String.(=) (String.suffix base_path 1) "/"
  then Uri.with_path uri (sprintf "%s%s" base_path append)
  else Uri.with_path uri (sprintf "%s/%s" base_path append)
