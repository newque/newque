module M : Persistence.Template

val create : string array -> index:string -> typename:string -> M.t Lwt.t
