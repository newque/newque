open Core.Std

type ack =
  | Instant
  | Saved
[@@deriving sexp]

type t = {
  ack: ack;
} [@@deriving sexp]

let create config_channel_write =
  let open Config_t in
  let ack = match config_channel_write.c_ack with
    | C_instant -> Instant
    | C_saved -> Saved
  in
  { ack }
