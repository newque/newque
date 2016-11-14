open Core.Std

type ('a, 'b) t = {
  left: 'a Queue.t;
  right: 'b Queue.t;
  max_time: float; (* milliseconds *)
  max_size: int;
  handler: 'a array -> 'b array -> int Lwt.t;
  mutable thread: unit Lwt.t sexp_opaque;
  mutable wake: unit Lwt.u sexp_opaque;
  mutable last_flush: float;
} [@@deriving sexp]

val create :
  max_time:float ->
  max_size:int ->
  handler:('a array -> 'b array -> int Lwt.t) ->
  ('a, 'b) t

val length : ('a, 'b) t -> int

val submit : ('a, 'b) t -> 'a array -> 'b array -> unit Lwt.t
