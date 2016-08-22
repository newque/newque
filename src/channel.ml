open Core.Std
open Lwt
open Sexplib.Conv

let log_path name = Fs.conf_chan_dir ^ name

type t = {
  name: string;
  endpoint_names: string list;
  durability: Durability.t;
  acknowledgement: Acknowledgement.t;
  separator: string;
  buffer_size: int;
  dealer: Dealer.t sexp_opaque;
} [@@deriving sexp]

let create name (conf_channel : Config_t.config_channel) =
  let open Config_t in
  {
    name;
    endpoint_names = conf_channel.endpoint_names;
    durability = conf_channel.durability;
    acknowledgement = conf_channel.acknowledgement;
    separator = conf_channel.separator;
    buffer_size = conf_channel.buffer_size;
    dealer = ();
  }

let push_single (chan: t) (msg : Message.t) = return_unit

let push_atomic (chan: t) (msgs : Message.t list) = return_unit
