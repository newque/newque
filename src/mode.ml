open Core.Std

module Write = struct
  type t = [
    | `Single
    | `Multiple
    | `Atomic
  ]
  let to_string (tag : t) = match tag with
    | `Single -> "Single"
    | `Multiple -> "Multiple"
    | `Atomic -> "Atomic"
end

module Read = struct
  type t = [
    | `One
    | `Many of int
    | `After_id of string
    | `After_ts of int
  ]
  let to_string (tag : t) = match tag with
    | `One -> "One"
    | `Many x -> Printf.sprintf "Many(%d) " x
    | `After_id s -> Printf.sprintf "After_id(%s)" s
    | `After_ts ts -> Printf.sprintf "After_ts(%d)" ts
end

module Count = struct
  type t = [
    | `Count
  ]
end

module Any = struct
  type t = [
      Write.t | Read.t | Count.t
  ]
end

type t = [
  | `Write of Write.t
  | `Read of Read.t
  | Count.t
]

(* Efficient, not pretty. *)
let of_string str : (Any.t, string) Result.t =
  match String.lowercase str with
  | "single" -> Ok `Single
  | "multiple" -> Ok `Multiple
  | "atomic" -> Ok `Atomic
  | "one" -> Ok `One
  | s -> begin match Util.split ~sep:" " s with
      | ["after_id"; id] -> Ok (`After_id id)
      | [name; v] ->
        begin match (name, (Util.parse_int v)) with
          | "many", Some n -> Ok (`Many n)
          | "after_ts", Some ts -> Ok (`After_ts ts)
          | _ -> Error str
        end
      | _ -> Error str
    end
  | _ -> Error str

let wrap (tag : Any.t) : t = match tag with
  | `Single -> `Write `Single
  | `Multiple -> `Write `Multiple
  | `Atomic -> `Write `Atomic
  | `One -> `Read `One
  | (`Many _) as x -> `Read x
  | (`After_id _) as x -> `Read x
  | (`After_ts _) as x-> `Read x
  | `Count -> `Count
