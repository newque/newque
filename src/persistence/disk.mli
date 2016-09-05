module M : Persistence.Template

val create : string -> string -> M.t Lwt.t
