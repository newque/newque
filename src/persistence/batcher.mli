open Core

type ('a, 'b, 'c) t

val create :
  max_time:float ->
  max_size:int ->
  handler:('a Collection.t -> 'b Collection.t -> 'c Lwt.t) ->
  ('a, 'b, 'c) t

val length : ('a, 'b, 'c) t -> int

val submit : ('a, 'b, 'c) t -> 'a Collection.t -> 'b Collection.t -> unit Lwt.t
