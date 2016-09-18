module M : Persistence.Template

val create : string -> chan_name:string -> avg_read:int -> M.t Lwt.t
