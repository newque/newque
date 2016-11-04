open Core.Std

type t = {
  format: Io_format.t;
} [@@deriving sexp]

let create config_channel_read =
  let open Config_t in
  { format = Io_format.create config_channel_read.c_format }
