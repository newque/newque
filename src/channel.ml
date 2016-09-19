open Core.Std
open Lwt

let log_path name = Fs.conf_chan_dir ^ name

type t = {
  name: string;
  endpoint_names: string list;
  push: Message.t array -> Id.t array -> Ack.t -> int Lwt.t sexp_opaque;
  pull: mode:Mode.Read.t -> Message.t array Lwt.t sexp_opaque;
  size: unit -> int64 Lwt.t sexp_opaque;
  ack: Ack.t;
  separator: string;
  buffer_size: int;
} [@@deriving sexp]

let create ?redis name (conf_channel : Config_t.config_channel) =
  let open Config_t in
  let module Persist = (val (match conf_channel.persistence with
    | `Memory ->
      let module Arg = struct
        module IO = Memory.M
        let create () = Memory.create ~chan_name:name ~avg_read:conf_channel.avg_read
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Disk ->
      let module Arg = struct
        module IO = Disk.M
        let create () = Disk.create Fs.data_chan_dir ~chan_name:name ~avg_read:conf_channel.avg_read
      end in
      (module Persistence.Make (Arg) : Persistence.S)

    | `Redis ->
      (* Option.value_exn is safe here because of the check in Configtools *)
      let {r_host; r_port; r_auth;} = Option.value_exn redis in
      let module Arg = struct
        module IO = Redis.M
        let create () = Redis.create r_host r_port r_auth
      end in
      (module Persistence.Make (Arg) : Persistence.S)
  ) : Persistence.S)
  in
  {
    name;
    endpoint_names = conf_channel.endpoint_names;
    push = Persist.push;
    pull = Persist.pull;
    size = Persist.size;
    ack = conf_channel.ack;
    separator = conf_channel.separator;
    buffer_size = conf_channel.buffer_size;
  }

let push (chan: t) (msgs : Message.t array) (ids: Id.t array) =
  chan.push msgs ids chan.ack

let pull (chan: t) ~(mode : Mode.Read.t) =
  chan.pull ~mode

let size (chan: t) () =
  chan.size ()
