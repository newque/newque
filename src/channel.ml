open Core.Std
open Lwt
open Sexplib.Conv

let log_path name = Fs.conf_chan_dir ^ name

type t = {
  name: string;
  endpoint_names: string list;
  push_single: chan_name:string -> Message.t -> Ack.t -> int Lwt.t;
  push_atomic: chan_name:string -> Message.t list -> Ack.t -> int Lwt.t;
  ack: Ack.t;
  separator: string;
  buffer_size: int;
} [@@deriving sexp]

let create name (conf_channel : Config_t.config_channel) =
  let open Config_t in
  let module Persist = (val (match conf_channel.persistence with
      | `Memory -> (module Memory.M : Persistence.S)
      | `Disk -> (module Disk.M : Persistence.S)
      | `Redis -> (module Redis.M : Persistence.S)
    ) : Persistence.S)
  in
  {
    name;
    endpoint_names = conf_channel.endpoint_names;
    push_single = Persist.push_single;
    push_atomic = Persist.push_atomic;
    ack = conf_channel.ack;
    separator = conf_channel.separator;
    buffer_size = conf_channel.buffer_size;
  }

let push_single (chan: t) (msg : Message.t) =
  chan.push_single ~chan_name:chan.name msg chan.ack

let push_atomic (chan: t) (msgs : Message.t list) =
  chan.push_atomic ~chan_name:chan.name msgs chan.ack
