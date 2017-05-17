type ack =
  | Instant
  | Saved

type json_validation = {
  schema_name: string;
  parallelism_threshold: int;
}

type scripting = {
  mappers: string array;
}

type batching = {
  max_time: float;
  max_size: int;
}

type t = {
  http_format: Http_format.t;
  ack: ack;
  forward: string list;
  json_validation: json_validation option;
  scripting: scripting option;
  batching: batching option;
}

val create : Config_t.config_channel_write -> t
