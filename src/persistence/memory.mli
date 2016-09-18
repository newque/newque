module M : Persistence.Template

val create : chan_name:string -> avg_read:int -> M.t Lwt.t
