open Core.Std
open Lwt

let log_path name = Fs.conf_chan_dir ^ name

type t = {
  name: string;
  endpoint_names: string list;
  push: Message.t array -> Id.t array -> Ack.t -> int Lwt.t sexp_opaque;
  pull_slice: int64 -> mode:Mode.Read.t -> string array Lwt.t sexp_opaque;
  pull_stream: int64 -> mode:Mode.Read.t -> string Lwt_stream.t Lwt.t sexp_opaque;
  size: unit -> int64 Lwt.t sexp_opaque;
  ack: Ack.t;
  separator: string;
  buffer_size: int;
  max_read: int64;
} [@@deriving sexp]

let create ?redis name (conf_channel : Config_t.config_channel) =
  let open Config_t in
  let module Persist = (val (match conf_channel.persistence with
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

    | `Redis ->
      (* Option.value_exn is safe here because of the check in Configtools *)
      let {r_host; r_port; r_auth;} = Option.value_exn redis in
      let module Arg = struct
        module IO = Redis.M
        let create () = Redis.create r_host r_port r_auth
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
    ack = conf_channel.ack;
    separator = conf_channel.separator;
    buffer_size = conf_channel.buffer_size;
    max_read = Int.to_int64 (conf_channel.max_read);
  }

let push chan msgs ids = chan.push msgs ids chan.ack

let pull_slice chan ~mode = chan.pull_slice chan.max_read ~mode

let pull_stream chan ~mode = chan.pull_stream chan.max_read ~mode

let size chan () = chan.size ()
