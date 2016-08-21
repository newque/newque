open Core.Std
open Sexplib.Conv
open Config_t

let log_path name = Fs.conf_chan_dir ^ name

type t = {
  name: string;
  endpoint_names: string list;
  durability: Durability.t;
  acknowledgement: Acknowledgement.t;
} [@@deriving sexp]
