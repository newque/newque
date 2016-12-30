module M : Persistence.Template

val create : chan_name:string -> string -> int -> M.t Lwt.t
