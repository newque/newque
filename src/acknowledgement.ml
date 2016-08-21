open Core.Std

type t = Config_t.config_acknowledgement

let sexp_of_t ack =
  let s = Sexp.Atom (Config_j.string_of_config_acknowledgement ack) in
  print_endline (Config_j.string_of_config_acknowledgement ack);
  s

let t_of_sexp sexp = Config_j.config_acknowledgement_of_string (Sexp.to_string sexp)
