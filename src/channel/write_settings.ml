open Core.Std

type ack =
  | Instant
  | Saved
[@@deriving sexp]

type t = {
  ack: ack;
  format: Io_format.t;
  copy_to: string list;
} [@@deriving sexp]

let create config_channel_write =
  let open Config_t in
  let ack = match config_channel_write.c_ack with
    | C_instant -> Instant
    | C_saved -> Saved
  in
  let format = Io_format.create config_channel_write.c_format in
  let copy_to = config_channel_write.c_copy_to in
  { ack; format; copy_to; }
