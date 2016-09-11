type t [@@deriving sexp]

val create : string -> t Lwt.t

val insert : t -> msgs:string list -> ids:string list -> int Lwt.t
