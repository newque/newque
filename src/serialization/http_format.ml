type t =
  | Plaintext
  | Json
[@@deriving sexp]

let create c_format =
  let open Config_t in
  match c_format with
  | C_plaintext -> Plaintext
  | C_json -> Json
