module M : Persistence.Template

val create : string -> int -> string option -> M.t Lwt.t
