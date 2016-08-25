open Core.Std

type t = Config_t.config_acknowledgement

let sexp_of_t ack = Sexp.Atom (Config_j.string_of_config_acknowledgement ack)

let t_of_sexp sexp = Config_j.config_acknowledgement_of_string (Sexp.to_string sexp)
