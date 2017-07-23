type t =
  | Production
  | Development

let create c_environment =
  let open Config_t in
  match c_environment with
  | C_production -> Production
  | C_development -> Development

let to_string env =
  let open Config_t in
  match env with
  | Production -> "production"
  | Development -> "development"
