type t [@@deriving sexp]

val create : string -> avg_read:int -> t Lwt.t

val push : t -> msgs:string array -> ids:string array -> int Lwt.t

val pull : t -> mode:Mode.Read.t -> string array Lwt.t

val size : t -> int64 Lwt.t
