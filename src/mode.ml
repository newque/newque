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
    | `After_id of string
    | `After_ts of int
  ]
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

let wrap (tag : Any.t) : t = match tag with
  | `Single -> `Write `Single
  | `Multiple -> `Write `Multiple
  | `Atomic -> `Write `Atomic
  | `One -> `Read `One
  | (`After_id _) as x -> `Read x
  | (`After_ts _) as x-> `Read x
  | `Count -> `Count
