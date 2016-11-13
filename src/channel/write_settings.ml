open Core.Std

type ack =
  | Instant
  | Saved
[@@deriving sexp]

type batching = {
  max_time: float;
  max_size: int;
} [@@deriving sexp]

type t = {
  ack: ack;
  format: Io_format.t;
  copy_to: string list;
  batching: batching option;
} [@@deriving sexp]

let create config_channel_write =
  let open Config_t in
  let ack = match config_channel_write.c_ack with
    | C_instant -> Instant
    | C_saved -> Saved
  in
  let format = Io_format.create config_channel_write.c_format in
  let copy_to = config_channel_write.c_copy_to in
  let batching = Option.map config_channel_write.c_batching ~f:(fun conf_batching ->
      {
        max_time = conf_batching.c_max_time;
        max_size = conf_batching.c_max_size;
      }
    ) in
  { ack; format; copy_to; batching; }
