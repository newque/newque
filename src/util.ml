open Core.Std
open Lwt

let split ~sep str =
  let delim = Str.regexp_string sep in
  Str.split_delim delim str

let rev_zip_group ~size ll1 ll2 =
  let rec aux l1 l2 cur cur_len acc =
    match (l1, l2) with
    | _ when cur_len >= size -> aux l1 l2 [] 0 (cur::acc)
    | ([], []) when cur_len = 0 -> return acc
    | ([], []) -> return (cur::acc)
    | ((h1::t1), (h2::t2)) -> aux t1 t2 ((h1, h2)::cur) (cur_len+1) acc
    | _ -> fail_with (Printf.sprintf "Different list lengths: %d and %d" (List.length ll1) (List.length ll2))
  in
  let%lwt divided = aux ll1 ll2 [] 0 [] in
  return (divided)

(* TODO: Decide what to do with these synchronous exceptions *)
let json_of_sexp sexp =
  let is_assoc sexp =
    match sexp with
    | Sexp.List [Sexp.Atom _; _] -> true
    | _ -> false
  in
  let has_dup_keys ll =
    List.contains_dup (List.map ll ~f:(fun sexp ->
        match sexp with
        | Sexp.List [(Sexp.Atom key); _] -> key
        | _ -> failwith "Unreachable"
      ))
  in
  let rec traverse sexp =
    match sexp with
    | Sexp.List ll when (List.for_all ll ~f:is_assoc) && not (has_dup_keys ll) ->
      `Assoc (List.map ll ~f:(function
          | Sexp.List [Sexp.Atom head; tail] -> (head, (traverse tail))
          | _ -> failwith "Unreachable"
        ))
    | Sexp.List ll -> `List (List.map ~f:traverse ll)
    | Sexp.Atom x ->
      try
        let f = Float.of_string x in
        let i = Float.to_int f in
        if (Int.to_float i) = f then `Int i else `Float f
      with _ -> `String x
  in
  traverse sexp

let string_of_sexp ?(pretty=true) sexp =
  if pretty then Yojson.Basic.pretty_to_string (json_of_sexp sexp)
  else Yojson.Basic.to_string (json_of_sexp sexp)

(* TODO: Catch potential errors *)
let sexp_of_atdgen str =
  match Yojson.Basic.from_string str with
  | `String s -> Sexp.Atom s
  | _ -> Sexp.Atom str
