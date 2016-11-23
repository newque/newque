open Core.Std
open Lwt

type t = {
  name: string;
  endpoint_names: string list;
  push: Message.t -> Id.t array -> int Lwt.t sexp_opaque;
  pull_slice: int64 -> mode:Mode.Read.t -> only_once:bool -> Persistence.slice Lwt.t sexp_opaque;
  pull_stream: int64 -> mode:Mode.Read.t -> only_once:bool -> string Lwt_stream.t Lwt.t sexp_opaque;
  size: unit -> int64 Lwt.t sexp_opaque;
  delete: unit -> unit Lwt.t sexp_opaque;
  health: unit -> string list Lwt.t sexp_opaque;
  emptiable: bool;
  raw: bool;
  read: Read_settings.t option;
  write: Write_settings.t option;
  separator: string;
  buffer_size: int;
  max_read: int64;
} [@@deriving sexp]

let create name conf_channel =
  let open Config_t in

  let read = Option.map conf_channel.read_settings ~f:Read_settings.create in
  let stream_slice_size = Option.value_map read ~default:Int64.max_value ~f:(fun r -> r.Read_settings.stream_slice_size) in

  let write = Option.map conf_channel.write_settings ~f:Write_settings.create in
  let batching = Option.bind write (fun w -> w.Write_settings.batching) in

  let module Persist = (val (match conf_channel.persistence_settings with
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
        let create () = Local.create ~file:(Printf.sprintf "%s%s.data" Fs.data_chan_dir name) ~chan_name:name ~avg_read:conf_channel.avg_read
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Remote_http remote ->
      let module Arg = struct
        module IO = Remote.M
        let create () = Remote.create
            (if remote.append_chan_name
             then Array.map ~f:(fun b -> Printf.sprintf "%s%s" b name) remote.base_urls
             else remote.base_urls)
            remote.base_headers
            ~input:remote.input_format
            ~output:remote.output_format
            ~chan_separator:conf_channel.separator
        let stream_slice_size = stream_slice_size
        let raw = conf_channel.raw
        let batching = batching
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Elasticsearch es ->
      if not conf_channel.raw then failwith (Printf.sprintf "Channel [%s] has persistence type [elasticsearch] but 'raw' is not set to true" name) else
      if Option.is_some read then failwith (Printf.sprintf "Channel [%s] has persistence type [elasticsearch] but is not write-only" name) else
      if conf_channel.emptiable then failwith (Printf.sprintf "Channel [%s] has persistence type [elasticsearch] but is emptiable" name) else
      let module Arg = struct
        module IO = Elasticsearch.M
        let create () = Elasticsearch.create es.base_urls ~index:es.index ~typename:es.typename
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
  {
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

let push chan msgs ids = chan.push msgs ids

let pull_slice chan ~mode ~limit = chan.pull_slice (Int64.min limit chan.max_read) ~mode

let pull_stream chan ~mode = chan.pull_stream chan.max_read ~mode

let size chan = chan.size ()

let delete chan = chan.delete ()

let health chan = chan.health ()
