open Core

type 'a t

val of_array : 'a array -> 'a t
val of_list : 'a list -> 'a t
val of_queue : 'a Queue.t -> 'a t
val empty : 'a t
val singleton : 'a -> 'a t

val length : 'a t -> int
val is_empty : 'a t -> bool

val map : f:('a -> 'a) -> 'a t -> 'a t
val concat_map : f:('a -> 'a list) -> 'a t -> 'a t

val to_array : 'a t -> 'a t * 'a array
val to_array_map : f:('a -> 'b) -> 'a t -> 'b t * 'b array
val to_array_concat_map : f:('a -> 'b list) -> 'a t -> 'b t * 'b array

val to_list : 'a t -> 'a t * 'a list
val to_list_map : f:('a -> 'b) -> 'a t -> 'b t * 'b list
val to_list_concat_map : f:('a -> 'b list) -> 'a t -> 'b t * 'b list

val to_coll_map : f:('a -> 'b) -> 'a t -> 'b t
val to_coll_concat_map : f:('a -> 'b list) -> 'a t -> 'b t

val iter : 'a t -> f:('a -> unit) -> unit
val iteri : 'a t -> f:(int -> 'a -> unit) -> unit
val fold : 'a t -> init:'accum -> f:('accum -> 'a -> 'accum) -> 'accum
val foldi : 'a t -> init:'accum -> f:(int -> 'accum -> 'a -> 'accum) -> 'accum

val add_to_queue : 'a t -> 'a Queue.t -> unit
val concat_string : sep:string -> string t -> string
val to_list_mapi_two : 'a t -> 'b t -> f:(int -> 'a -> 'b -> 'c) -> 'c t * 'c list
val to_list_concat_mapi_two : 'a t -> 'b t -> f:(int -> 'a -> 'b -> 'c list) -> 'c t * 'c list
val concat_mapi_two : 'a t -> 'b t -> f:(int -> 'a -> 'b -> 'c list) -> 'c t

val split : every:int -> 'a t -> 'a t list

val to_list_or_array : 'a t -> [ `List of 'a list | `Array of 'a array ]
val first : 'a t -> 'a option
