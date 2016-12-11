open Core.Std
open Lwt

type t = {
  conf_channel: Config_t.config_channel;
  name: string;
  endpoint_names: string list;
  push: Message.t -> Id.t array -> int Lwt.t;
  pull_slice: int64 -> mode:Mode.Read.t -> only_once:bool -> Persistence.slice Lwt.t;
  pull_stream: int64 -> mode:Mode.Read.t -> only_once:bool -> string Lwt_stream.t Lwt.t;
  size: unit -> int64 Lwt.t;
  delete: unit -> unit Lwt.t;
  health: unit -> string list Lwt.t;
  emptiable: bool;
  raw: bool;
  read: Read_settings.t option;
  write: Write_settings.t option;
  separator: string;
  buffer_size: int;
  max_read: int64;
}

let create name conf_channel =
  let open Config_t in

  let read = Option.map conf_channel.read_settings ~f:Read_settings.create in
  let stream_slice_size = Option.value_map read ~default:Int64.max_value ~f:(fun r -> r.Read_settings.stream_slice_size) in

  let write = Option.map conf_channel.write_settings ~f:Write_settings.create in
  let batching = Option.bind write (fun w -> w.Write_settings.batching) in

  let module Persist = (val (match conf_channel.backend_settings with
    | `None ->
      let module Arg = struct
        module IO = None.M
        let create () = None.create ()
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Memory ->
      let module Arg = struct
        module IO = Local.M
        let create () = Local.create ~file:":memory:" ~chan_name:name ~avg_read:conf_channel.avg_read
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Disk ->
      let module Arg = struct
        module IO = Local.M
        let create () = Local.create ~file:(sprintf "%s%s.data" Fs.data_chan_dir name) ~chan_name:name ~avg_read:conf_channel.avg_read
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Http_proxy httpproxy ->
      let module Arg = struct
        module IO = Http_proxy.M
        let create () = Http_proxy.create
            ~chan_name:name
            (if httpproxy.append_chan_name
             then Array.map ~f:(fun b -> sprintf "%s%s" b name) httpproxy.base_urls
             else httpproxy.base_urls)
            httpproxy.base_headers
            httpproxy.timeout
            ~input:httpproxy.input_format
            ~output:httpproxy.output_format
            ~chan_separator:conf_channel.separator
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Pubsub pubsub ->
      if not conf_channel.raw then failwith (sprintf "Channel [%s] has backend type [pubsub], setting 'raw' must be set to true" name) else
      if Option.is_some read then failwith (sprintf "Channel [%s] has backend type [pubsub], reading must be disabled" name) else
      if conf_channel.emptiable then failwith (sprintf "Channel [%s] has backend type [pubsub], setting 'emptiable' must be set to false" name) else
      let module Arg = struct
        module IO = Pubsub.M
        let create () = Pubsub.create
            ~chan_name:name
            pubsub.p_host
            pubsub.p_port
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Fifo fifo ->
      let module Arg = struct
        module IO = Fifo.M
        let create () = Fifo.create
            ~chan_name:name
            ~host:fifo.f_host
            ~port:fifo.f_port
            ~timeout_ms:fifo.f_timeout
            ~health_time_limit_ms:fifo.f_health_time_limit
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Elasticsearch es ->
      if not conf_channel.raw then failwith (sprintf "Channel [%s] has backend type [elasticsearch], setting 'raw' must be set to true" name) else
      if Option.is_some read then failwith (sprintf "Channel [%s] has backend type [elasticsearch], reading must be disabled" name) else
      if conf_channel.emptiable then failwith (sprintf "Channel [%s] has backend type [elasticsearch], setting 'emptiable' must be set to false" name) else
      let module Arg = struct
        module IO = Elasticsearch.M
        let create () = Elasticsearch.create
            es.base_urls
            ~index:es.index
            ~typename:es.typename
            es.timeout
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Redis redis ->
      let module Arg = struct
        module IO = Redis.M
        let create () = Redis.create redis.redis_host redis.redis_port redis.redis_auth
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)
  ) : Persistence.S)
  in
  let instance = {
    conf_channel;
    name;
    endpoint_names = conf_channel.endpoint_names;
    push = Persist.push;
    pull_slice = Persist.pull_slice;
    pull_stream = Persist.pull_stream;
    size = Persist.size;
    delete = Persist.delete;
    health = Persist.health;
    emptiable = conf_channel.emptiable;
    raw = conf_channel.raw;
    read = Option.map conf_channel.read_settings ~f:Read_settings.create;
    write;
    separator = conf_channel.separator;
    buffer_size = conf_channel.buffer_size;
    max_read = Int.to_int64 (conf_channel.max_read);
  }
  in
  let%lwt () = Persist.ready () in
  return instance

let push chan msgs ids = chan.push msgs ids

let pull_slice chan ~mode ~limit = chan.pull_slice (Int64.min limit chan.max_read) ~mode

let pull_stream chan ~mode = chan.pull_stream chan.max_read ~mode

let size chan = chan.size ()

let delete chan = chan.delete ()

let health chan = chan.health ()

let to_json chan = Yojson.Basic.from_string (Config_j.string_of_config_channel chan.conf_channel)
