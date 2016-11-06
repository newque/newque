open Core.Std
open Lwt

let log_path name = Fs.conf_chan_dir ^ name

type t = {
  name: string;
  endpoint_names: string list;
  push: Message.t array -> Id.t array -> int Lwt.t sexp_opaque;
  pull_slice: int64 -> mode:Mode.Read.t -> only_once:bool -> Persistence.slice Lwt.t sexp_opaque;
  pull_stream: int64 -> mode:Mode.Read.t -> only_once:bool -> string Lwt_stream.t Lwt.t sexp_opaque;
  size: unit -> int64 Lwt.t sexp_opaque;
  read: Read_settings.t option;
  write: Write_settings.t option;
  separator: string;
  buffer_size: int;
  max_read: int64;
} [@@deriving sexp]

let create name conf_channel =
  let open Config_t in
  let module Persist = (val (match conf_channel.persistence_settings with
    | `Memory ->
      let module Arg = struct
        module IO = Local.M
        let create () = Local.create ~file:":memory:" ~chan_name:name ~avg_read:conf_channel.avg_read
        let read_batch_size = Local.read_batch_size
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Disk ->
      let module Arg = struct
        module IO = Local.M
        let create () = Local.create ~file:(Printf.sprintf "%s%s.data" Fs.data_chan_dir name) ~chan_name:name ~avg_read:conf_channel.avg_read
        let read_batch_size = Local.read_batch_size
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Remote_http remote ->
      let module Arg = struct
        module IO = Remote.M
        let create () = Remote.create remote.base_urls ~input:remote.input_format ~output:remote.output_format
        let read_batch_size = Remote.read_batch_size
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Redis redis ->
      let module Arg = struct
        module IO = Redis.M
        let create () = Redis.create redis.redis_host redis.redis_port redis.redis_auth
        let read_batch_size = Redis.read_batch_size
      end in
      (module Persistence.Make (Arg) : Persistence.S)
  ) : Persistence.S)
  in
  {
    name;
    endpoint_names = conf_channel.endpoint_names;
    push = Persist.push;
    pull_slice = Persist.pull_slice;
    pull_stream = Persist.pull_stream;
    size = Persist.size;
    read = Option.map conf_channel.read_settings ~f:Read_settings.create;
    write = Option.map conf_channel.write_settings ~f:Write_settings.create;
    separator = conf_channel.separator;
    buffer_size = conf_channel.buffer_size;
    max_read = Int.to_int64 (conf_channel.max_read);
  }

let push chan msgs ids = chan.push msgs ids

let pull_slice chan ~mode = chan.pull_slice chan.max_read ~mode

let pull_stream chan ~mode = chan.pull_stream chan.max_read ~mode

let size chan () = chan.size ()
