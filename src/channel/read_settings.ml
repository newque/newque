open Core.Std

type t = {
  format: Io_format.t;
  stream_slice_size: int64;
  only_once: bool;
} [@@deriving sexp]

let create config_channel_read =
  let open Config_t in
  {
    format = Io_format.create config_channel_read.c_format;
    stream_slice_size = Int.to_int64 (config_channel_read.c_stream_slice_size);
    only_once = config_channel_read.c_only_once;
  }
