open Core.Std

type ack =
  | Instant
  | Saved

type batching = {
  max_time: float;
  max_size: int;
}

type t = {
  http_format: Http_format.t;
  ack: ack;
  forward: string list;
  batching: batching option;
}

let create config_channel_write =
  let open Config_t in
  let ack = match config_channel_write.c_ack with
    | C_instant -> Instant
    | C_saved -> Saved
  in
  let http_format = Http_format.create config_channel_write.c_http_format in
  let forward = config_channel_write.c_forward in
  let batching = Option.map config_channel_write.c_batching ~f:(fun conf_batching ->
      {
        max_time = conf_batching.c_max_time;
        max_size = conf_batching.c_max_size;
      }
    ) in
  { http_format; ack; forward; batching; }
