type t = {
  http_format: Http_format.t;
  stream_slice_size: int64;
  only_once: bool;
}

val create : Config_t.config_channel_read -> t
