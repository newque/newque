open Core

type t = {
  http_format: Http_format.t;
  stream_slice_size: int64;
  only_once: bool;
}

let create config_channel_read =
  let open Config_t in
  {
    http_format = Http_format.create config_channel_read.c_http_format;
    stream_slice_size = Int.to_int64 (config_channel_read.c_stream_slice_size);
    only_once = config_channel_read.c_only_once;
  }
