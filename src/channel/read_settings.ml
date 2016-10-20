open Core.Std

type format =
  | Plaintext
  | Json
[@@deriving sexp]

type t = {
  format: format;
} [@@deriving sexp]

let create config_channel_read =
  let open Config_t in
  let format = match config_channel_read.c_format with
    | C_plaintext -> Plaintext
    | C_json -> Json
  in
  { format }
