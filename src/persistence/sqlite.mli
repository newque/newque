type t [@@deriving sexp]

val create : string -> avg_read:int -> t Lwt.t

val close : t -> unit Lwt.t

val push : t -> msgs:string array -> ids:string array -> int Lwt.t

(* Returns the last rowid in an option *)
val pull :
  t ->
  search:Persistence.search ->
  (* Returns the last rowid as first option *)
  (* Returns the last id and timens as second option if fetch_last is true *)
  fetch_last:bool ->
  (string array * int64 option * (string * int64) option) Lwt.t

val size : t -> int64 Lwt.t
