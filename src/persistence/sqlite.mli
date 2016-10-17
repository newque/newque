type t [@@deriving sexp]

val create : string -> avg_read:int -> t Lwt.t

val close : t -> unit Lwt.t

val push : t -> msgs:string array -> ids:string array -> int Lwt.t

(* Returns the last rowid *)
val pull : t -> search:Persistence.search -> (string array * int64) Lwt.t

val size : t -> int64 Lwt.t
