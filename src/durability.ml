open Core.Std

type t = Config_t.config_durability

let sexp_of_t dur = Sexp.Atom (Config_j.string_of_config_durability dur)

let t_of_sexp sexp = Config_j.config_durability_of_string (Sexp.to_string sexp)
