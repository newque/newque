open Core.Std
open Sexplib.Conv
open Config_t

let log_path name = Fs.conf_chan_dir ^ name

type t = {
  name: string;
  endpoint_names: string list;
} [@@deriving sexp]

type durability = Config_t.config_durability
let sexp_of_durability dur = Sexp.Atom (Config_j.string_of_config_durability dur)
let durability_of_sexp sexp = Config_j.config_durability_of_string (Sexp.to_string sexp)

type acknowledgement = Config_t.config_acknowledgement
let sexp_of_acknowledgement ack = Sexp.Atom (Config_j.string_of_config_acknowledgement ack)
let acknowledgement_of_sexp sexp = Config_j.config_acknowledgement_of_string (Sexp.to_string sexp)

