module M : Persistence.Template

val create : file:string -> chan_name:string -> avg_read:int -> insert_batch_size:int -> M.t Lwt.t
