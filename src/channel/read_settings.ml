open Core.Std

type t = {
  format: Io_format.t;
} [@@deriving sexp]

let create config_channel_read =
  let open Config_t in
  let format = match config_channel_read.c_format with
    | C_plaintext -> Io_format.Plaintext
    | C_json -> Io_format.Json
  in
  { format }
