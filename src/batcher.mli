open Core.Std

type ('a, 'b, 'c) t

val create :
  max_time:float ->
  max_size:int ->
  handler:('a array -> 'b array -> 'c Lwt.t) ->
  ('a, 'b, 'c) t

val length : ('a, 'b, 'c) t -> int

val submit : ('a, 'b, 'c) t -> 'a array -> 'b array -> unit Lwt.t
