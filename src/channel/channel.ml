open Core
open Lwt

type t = {
  conf_channel: Config_t.config_channel;
  name: string;
  endpoint_names: string list;
  push: Message.t -> Id.t Collection.t -> int Lwt.t;
  pull_slice: int64 -> mode:Mode.Read.t -> only_once:bool -> Persistence.slice Lwt.t;
  pull_stream: int64 -> mode:Mode.Read.t -> only_once:bool -> string Lwt_stream.t Lwt.t;
  size: unit -> int64 Lwt.t;
  delete: unit -> unit Lwt.t;
  health: unit -> string list Lwt.t;
  emptiable: bool;
  raw: bool;
  read: Read_settings.t option;
  write: Write_settings.t option;
  splitter: Util.splitter;
  buffer_size: int;
  max_read: int64;
}

let create name conf_channel =
  let open Config_t in

  let read = Option.map conf_channel.read_settings ~f:Read_settings.create in
  let stream_slice_size = Option.value_map read ~default:Int64.max_value ~f:(fun r -> r.Read_settings.stream_slice_size) in

  let write = Option.map conf_channel.write_settings ~f:Write_settings.create in
  let json_validation = Option.bind write (fun w -> w.Write_settings.json_validation) in
  let scripting = Option.bind write (fun w -> w.Write_settings.scripting) in
  let batching = Option.bind write (fun w -> w.Write_settings.batching) in

  Option.iter scripting ~f:(fun scripting ->
    if Array.length scripting.Write_settings.mappers = 0
    then failwith (sprintf "Channel [%s] has scripting enabled, but no script is specified" name)
  );

  if String.is_empty conf_channel.separator
  then failwith (sprintf "Channel [%s] has invalid separator (empty string)" name) else

  let splitter = Util.make_splitter ~sep:conf_channel.separator in

  let module Persist = (val (match conf_channel.backend_settings with
    | `None ->
      let module Arg = struct
        module IO = None.M
        let create () = None.create ()
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let json_validation = json_validation
        let scripting = scripting
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Memory ->
      let module Arg = struct
        module IO = Local.M
        let create () = Local.create
            ~file:":memory:"
            ~chan_name:name
            ~avg_read:conf_channel.avg_read
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let json_validation = json_validation
        let scripting = scripting
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Disk ->
      let module Arg = struct
        module IO = Local.M
        let create () = Local.create
            ~file:(sprintf "%s%s.data" Fs.data_chan_dir name)
            ~chan_name:name
            ~avg_read:conf_channel.avg_read
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let json_validation = json_validation
        let scripting = scripting
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
            ~splitter
            ~chan_separator:conf_channel.separator
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let json_validation = json_validation
        let scripting = scripting
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
            ~host:pubsub.p_host
            ~port:pubsub.p_port
            ~socket_settings:pubsub.p_socket_settings
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let json_validation = json_validation
        let scripting = scripting
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Fifo fifo ->
      let timeout_ms = fifo.f_timeout in
      let health_time_limit_ms = fifo.f_health_time_limit in
      if Float.(<) timeout_ms health_time_limit_ms then failwith (sprintf
            "Channel [%s] has backend type [fifo], setting 'timeout' (%.f) must not be smaller than 'healthTimeLimit' (%.f)"
            name timeout_ms health_time_limit_ms
        )
      else
      let module Arg = struct
        module IO = Fifo.M
        let create () = Fifo.create
            ~chan_name:name
            ~host:fifo.f_host
            ~port:fifo.f_port
            ~socket_settings:fifo.f_socket_settings
            ~timeout_ms
            ~health_time_limit_ms
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let json_validation = json_validation
        let scripting = scripting
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
        let json_validation = json_validation
        let scripting = scripting
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Redis redis ->
      let module Arg = struct
        module IO = Redis_.M
        let create () = Redis_.create
            ~chan_name:name
            redis.redis_host
            redis.redis_port
            ~auth:redis.redis_auth
            ~database:redis.redis_database
            ~pool_size:redis.redis_pool_size
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let json_validation = json_validation
        let scripting = scripting
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Redis_pubsub redis_pubsub ->
      if not conf_channel.raw then failwith (sprintf "Channel [%s] has backend type [redis_pubsub], setting 'raw' must be set to true" name) else
      if Option.is_some read then failwith (sprintf "Channel [%s] has backend type [redis_pubsub], reading must be disabled" name) else
      if conf_channel.emptiable then failwith (sprintf "Channel [%s] has backend type [redis_pubsub], setting 'emptiable' must be set to false" name) else
      let module Arg = struct
        module IO = Redis_pubsub.M
        let create () = Redis_pubsub.create
            ~chan_name:name
            redis_pubsub.redis_pubsub_host
            redis_pubsub.redis_pubsub_port
            ~auth:redis_pubsub.redis_pubsub_auth
            ~database:redis_pubsub.redis_pubsub_database
            ~pool_size:redis_pubsub.redis_pubsub_pool_size
            ~broadcast:redis_pubsub.redis_pubsub_broadcast
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let json_validation = json_validation
        let scripting = scripting
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
    splitter;
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
