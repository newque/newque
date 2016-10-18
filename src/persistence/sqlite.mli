type t [@@deriving sexp]

val create : string -> avg_read:int -> t Lwt.t

val close : t -> unit Lwt.t

val push : t -> msgs:string array -> ids:string array -> int Lwt.t

(* Returns the last rowid in an option *)
val pull : t -> search:Persistence.search -> (string array * int64 option) Lwt.t

(* Returns the id and timens for a rowid *)
val single : t -> rowid:int64 -> (string * int64) Lwt.t

val size : t -> int64 Lwt.t
