type t [@@deriving sexp]

val create : string -> t Lwt.t

val push : t -> msgs:string list -> ids:string list -> int Lwt.t

val size : t -> int Lwt.t
