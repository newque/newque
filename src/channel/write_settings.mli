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

val create : Config_t.config_channel_write -> t
