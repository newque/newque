open Core.Std
open Lwt

let split ~sep str =
  let delim = Str.regexp_string sep in
  Str.split_delim delim str

let parse_int64 str =
  try Some (Int64.of_string str)
  with _ -> None

(* This was rewritten in c/fortran style for efficiency *)
let zip_group ~size arr1 arr2 =
  if Array.length arr1 <> Array.length arr2 then
    fail_with (Printf.sprintf "Different array lengths: %d and %d" (Array.length arr1) (Array.length arr2))
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
  let queue = Queue.create ~capacity:batch_size () in
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

(* TODO: Decide what to do with these "impossible" synchronous exceptions *)
let is_assoc sexp =
  match sexp with
  | Sexp.List [Sexp.Atom _; _] -> true
  | _ -> false
let has_dup_keys ll =
  List.contains_dup (List.map ll ~f:(fun sexp ->
      match sexp with
      | Sexp.List [(Sexp.Atom key); _] -> key
      | _ -> failwith "Unreachable"
    ))
let rec json_of_sexp sexp =
  match sexp with
  | Sexp.List ll when (List.for_all ll ~f:is_assoc) && not (has_dup_keys ll) ->
    `Assoc (List.map ll ~f:(function
        | Sexp.List [Sexp.Atom head; tail] -> (head, (json_of_sexp tail))
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
    Sexp.List (List.map ll ~f:(fun (key, json) ->
        Sexp.List [Sexp.Atom key; sexp_of_json_exn json]
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

(* TODO: Catch potential errors *)
let sexp_of_atdgen str =
  match Yojson.Basic.from_string str with
  | `String s -> Sexp.Atom s
  | _ -> Sexp.Atom str
