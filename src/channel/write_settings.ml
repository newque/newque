open Core.Std

type ack =
  | Instant
  | Saved
[@@deriving sexp]

type t = {
  ack: ack;
  copy_to: string list;
} [@@deriving sexp]

let create config_channel_write =
  let open Config_t in
  let ack = match config_channel_write.c_ack with
    | C_instant -> Instant
    | C_saved -> Saved
  in
  let copy_to = config_channel_write.c_copy_to in
  { ack; copy_to; }
