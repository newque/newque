open Core.Std

type 'a structure =
  | List : 'a list -> 'a structure
  | Array : 'a array -> 'a structure
  | Both : ('a array * 'a list) -> 'a structure
  | Queue : 'a Queue.t -> 'a structure

type 'a mapper =
  | Flat_map of ('a -> 'a)
  | Concat_map of ('a -> 'a list)

type 'a t = {
  data: 'a structure;
  maps: 'a mapper Fqueue.t;
}

(* INIT *)
let of_array arr = { data = Array arr; maps = Fqueue.empty }
let of_list ll = { data = List ll; maps = Fqueue.empty }
let of_queue q = { data = Queue q; maps = Fqueue.empty }
let empty = { data = List []; maps = Fqueue.empty }
let singleton v = { data = List [v]; maps = Fqueue.empty }

(* BASIC OPERATIONS *)
let length coll =
  match coll.data with
  | List ll -> List.length ll
  | Array arr | Both (arr, _) -> Array.length arr
  | Queue q -> Queue.length q

let is_empty coll = Int.(=) (length coll) 0

let map ~f coll =
  { coll with maps = Fqueue.enqueue coll.maps (Flat_map f) }

let concat_map ~f coll =
  { coll with maps = Fqueue.enqueue coll.maps (Concat_map f) }


(* STEPS *)
let make_array data =
  match data with
  | List ll ->
    let arr = List.to_array ll in
    (Both (arr, ll)), arr
  | Array arr | Both (arr, _) ->
    data, arr
  | Queue q ->
    let arr = Queue.to_array q in
    (Array arr), arr

let make_list data =
  match data with
  | List ll | Both (_, ll) ->
    data, ll
  | Array arr ->
    let ll = Array.to_list arr in
    (Both (arr, ll)), ll
  | Queue q ->
    let ll = Queue.to_list q in
    (List ll), ll

let towards_array_map ~mapper data =
  let arr = match data with
    | List ll ->
      Array.of_list_map ~f:mapper ll
    | Array arr | Both (arr, _ ) ->
      Array.map ~f:mapper arr
    | Queue q ->
      Array.init (Queue.length q) ~f:(fun i -> mapper (Queue.get q i))
  in
  Array arr

let towards_list_map ~mapper data =
  let ll = match data with
    | List ll ->
      List.map ~f:mapper ll
    | Array arr | Both (arr, _ ) ->
      let last = (Array.length arr) - 1 in
      List.init (Array.length arr) ~f:(fun i -> mapper (Array.get arr (last - i)))
    | Queue q ->
      let last = (Queue.length q) - 1 in
      List.init (Queue.length q) ~f:(fun i -> mapper (Queue.get q (last - i)))
  in
  List ll

let towards_queue_map ~mapper data =
  match data with
  | List ll ->
    let queue = Queue.create ~capacity:(List.length ll) () in
    List.iter ll ~f:(fun x ->
      Queue.enqueue queue (mapper x)
    );
    Queue queue
  | Array arr | Both (arr, _ ) ->
    let queue = Queue.create ~capacity:(Array.length arr) () in
    Array.iter arr ~f:(fun x ->
      Queue.enqueue queue (mapper x)
    );
    Queue queue
  | Queue q ->
    Queue (Queue.map ~f:mapper q)

let towards_array_concat_map ~f ~mapper data =
  match mapper with
  | None ->
    begin match data with
      | List ll ->
        let queue = Queue.create ~capacity:(List.length ll) () in
        List.iter ll ~f:(fun x ->
          Queue.enqueue_all queue (f x)
        );
        Queue queue
      | Array arr | Both (arr, _ ) ->
        let queue = Queue.create ~capacity:(Array.length arr) () in
        Array.iter arr ~f:(fun x ->
          Queue.enqueue_all queue (f x)
        );
        Queue queue
      | Queue q ->
        Queue (Queue.concat_map ~f q)
    end
  | Some mapper ->
    begin match data with
      | List ll ->
        let queue = Queue.create ~capacity:(List.length ll) () in
        List.iter ll ~f:(fun x ->
          Queue.enqueue_all queue (f (mapper x))
        );
        Queue queue
      | Array arr | Both (arr, _ ) ->
        let queue = Queue.create ~capacity:(Array.length arr) () in
        Array.iter arr ~f:(fun x ->
          Queue.enqueue_all queue (f (mapper x))
        );
        Queue queue
      | Queue q ->
        let queue = Queue.create ~capacity:(Queue.length q) () in
        Queue.iter q ~f:(fun x ->
          Queue.enqueue_all queue (f (mapper x))
        );
        Queue queue
    end

let towards_list_concat_map ~f ~mapper data =
  match mapper with
  | None ->
    begin match data with
      | List ll ->
        List (List.concat_map ~f ll)
      | Array arr | Both (arr, _ ) ->
        let queue = Queue.create ~capacity:(Array.length arr) () in
        Array.iter arr ~f:(fun x ->
          Queue.enqueue_all queue (f x)
        );
        Queue queue
      | Queue q ->
        Queue (Queue.concat_map ~f q)
    end
  | Some mapper ->
    begin match data with
      | List ll ->
        let queue = Queue.create ~capacity:(List.length ll) () in
        List.iter ll ~f:(fun x ->
          Queue.enqueue_all queue (f (mapper x))
        );
        Queue queue
      | Array arr | Both (arr, _ ) ->
        let queue = Queue.create ~capacity:(Array.length arr) () in
        Array.iter arr ~f:(fun x ->
          Queue.enqueue_all queue (f (mapper x))
        );
        Queue queue
      | Queue q ->
        let queue = Queue.create ~capacity:(Queue.length q) () in
        Queue.iter q ~f:(fun x ->
          Queue.enqueue_all queue (f (mapper x))
        );
        Queue queue
    end

let towards_queue_concat_map = towards_array_concat_map

(* EXPORTS *)
let towards_array coll =
  let rec loop data mappers =
    match mappers with
    | [] ->
      data
    | (Flat_map flat1)::(Flat_map flat2)::tail ->
      loop data ((Flat_map (Fn.compose flat2 flat1))::tail)
    | (Flat_map flat)::(Concat_map concat)::tail ->
      loop (towards_array_concat_map ~f:concat ~mapper:(Some flat) data) tail
    | (Concat_map concat)::tail ->
      loop (towards_array_concat_map ~f:concat ~mapper:None data) tail
    | (Flat_map flat)::[] ->
      loop (towards_array_map ~mapper:flat data) []
  in
  loop coll.data (Fqueue.to_list coll.maps)

let to_array coll =
  let data, arr = make_array (towards_array coll) in
  { data; maps = Fqueue.empty }, arr

let to_array_map ~f coll =
  let rec loop data mappers =
    match mappers with
    | [] ->
      towards_array_map ~mapper:f data
    | (Flat_map flat1)::(Flat_map flat2)::tail ->
      loop data ((Flat_map (Fn.compose flat2 flat1))::tail)
    | (Flat_map flat)::(Concat_map concat)::tail ->
      loop (towards_array_concat_map ~f:concat ~mapper:(Some flat) data) tail
    | (Concat_map concat)::tail ->
      loop (towards_array_concat_map ~f:concat ~mapper:None data) tail
    | (Flat_map flat)::[] ->
      towards_array_map ~mapper:(Fn.compose f flat) data
  in
  let data, arr = make_array (loop coll.data (Fqueue.to_list coll.maps)) in
  { data; maps = Fqueue.empty }, arr

let to_array_concat_map ~f coll =
  let rec loop data mappers =
    match mappers with
    | [] ->
      towards_array_concat_map ~f ~mapper:None data
    | (Flat_map flat1)::(Flat_map flat2)::tail ->
      loop data ((Flat_map (Fn.compose flat2 flat1))::tail)
    | (Flat_map flat)::(Concat_map concat)::tail ->
      loop (towards_array_concat_map ~f:concat ~mapper:(Some flat) data) tail
    | (Concat_map concat)::tail ->
      loop (towards_array_concat_map ~f:concat ~mapper:None data) tail
    | (Flat_map flat)::[] ->
      towards_array_concat_map ~f ~mapper:(Some flat) data
  in
  let data, arr = make_array (loop coll.data (Fqueue.to_list coll.maps)) in
  { data; maps = Fqueue.empty }, arr

let towards_list coll =
  let rec loop data mappers =
    match mappers with
    | [] ->
      data
    | (Flat_map flat1)::(Flat_map flat2)::tail ->
      loop data ((Flat_map (Fn.compose flat2 flat1))::tail)
    | (Flat_map flat)::(Concat_map concat)::tail ->
      loop (towards_list_concat_map ~f:concat ~mapper:(Some flat) data) tail
    | (Concat_map concat)::tail ->
      loop (towards_list_concat_map ~f:concat ~mapper:None data) tail
    | (Flat_map flat)::[] ->
      loop (towards_list_map ~mapper:flat data) []
  in
  loop coll.data (Fqueue.to_list coll.maps)

let to_list coll =
  let data, ll = make_list (towards_list coll) in
  { data; maps = Fqueue.empty }, ll

let to_list_map ~f coll =
  let rec loop data mappers =
    match mappers with
    | [] ->
      towards_list_map ~mapper:f data
    | (Flat_map flat1)::(Flat_map flat2)::tail ->
      loop data ((Flat_map (Fn.compose flat2 flat1))::tail)
    | (Flat_map flat)::(Concat_map concat)::tail ->
      loop (towards_list_concat_map ~f:concat ~mapper:(Some flat) data) tail
    | (Concat_map concat)::tail ->
      loop (towards_list_concat_map ~f:concat ~mapper:None data) tail
    | (Flat_map flat)::[] ->
      towards_list_map ~mapper:(Fn.compose f flat) data
  in
  let data, ll = make_list (loop coll.data (Fqueue.to_list coll.maps)) in
  { data; maps = Fqueue.empty }, ll

let to_list_concat_map ~f coll =
  let rec loop data mappers =
    match mappers with
    | [] ->
      towards_list_concat_map ~f ~mapper:None data
    | (Flat_map flat1)::(Flat_map flat2)::tail ->
      loop data ((Flat_map (Fn.compose flat2 flat1))::tail)
    | (Flat_map flat)::(Concat_map concat)::tail ->
      loop (towards_list_concat_map ~f:concat ~mapper:(Some flat) data) tail
    | (Concat_map concat)::tail ->
      loop (towards_list_concat_map ~f:concat ~mapper:None data) tail
    | (Flat_map flat)::[] ->
      towards_list_concat_map ~f ~mapper:(Some flat) data
  in
  let data, ll = make_list (loop coll.data (Fqueue.to_list coll.maps)) in
  { data; maps = Fqueue.empty }, ll

let towards_queue coll =
  let rec loop data mappers =
    match mappers with
    | [] ->
      data
    | (Flat_map flat1)::(Flat_map flat2)::tail ->
      loop data ((Flat_map (Fn.compose flat2 flat1))::tail)
    | (Flat_map flat)::(Concat_map concat)::tail ->
      loop (towards_queue_concat_map ~f:concat ~mapper:(Some flat) data) tail
    | (Concat_map concat)::tail ->
      loop (towards_queue_concat_map ~f:concat ~mapper:None data) tail
    | (Flat_map flat)::[] ->
      loop (towards_queue_map ~mapper:flat data) []
  in
  loop coll.data (Fqueue.to_list coll.maps)

let apply_maps coll =
  match coll.data with
  | List _ -> towards_list coll
  | Array _ | Both _ -> towards_array coll
  | Queue _ -> towards_queue coll

let to_coll_map ~f coll =
  let rec loop data mappers =
    match mappers with
    | [] ->
      towards_queue_map ~mapper:f data
    | (Flat_map flat1)::(Flat_map flat2)::tail ->
      loop data ((Flat_map (Fn.compose flat2 flat1))::tail)
    | (Flat_map flat)::(Concat_map concat)::tail ->
      loop (towards_queue_concat_map ~f:concat ~mapper:(Some flat) data) tail
    | (Concat_map concat)::tail ->
      loop (towards_queue_concat_map ~f:concat ~mapper:None data) tail
    | (Flat_map flat)::[] ->
      towards_queue_map ~mapper:(Fn.compose f flat) data
  in
  let data = loop coll.data (Fqueue.to_list coll.maps) in
  { data; maps = Fqueue.empty }

let to_coll_concat_map ~f coll =
  let rec loop data mappers =
    match mappers with
    | [] ->
      towards_queue_concat_map ~f ~mapper:None data
    | (Flat_map flat1)::(Flat_map flat2)::tail ->
      loop data ((Flat_map (Fn.compose flat2 flat1))::tail)
    | (Flat_map flat)::(Concat_map concat)::tail ->
      loop (towards_queue_concat_map ~f:concat ~mapper:(Some flat) data) tail
    | (Concat_map concat)::tail ->
      loop (towards_queue_concat_map ~f:concat ~mapper:None data) tail
    | (Flat_map flat)::[] ->
      towards_queue_concat_map ~f ~mapper:(Some flat) data
  in
  let data = loop coll.data (Fqueue.to_list coll.maps) in
  { data; maps = Fqueue.empty }


(* HIGH LEVEL *)
let iter coll ~f =
  match towards_array coll with
  | List ll -> List.iter ~f ll
  | Array arr | Both (arr, _) -> Array.iter ~f arr
  | Queue q -> Queue.iter ~f q

let fold coll ~init ~f =
  match apply_maps coll with
  | List ll -> List.fold ~init ~f ll
  | Array arr | Both (arr, _) -> Array.fold ~init ~f arr
  | Queue q -> Queue.fold ~init ~f q

(* From https://github.com/janestreet/core_kernel/blob/39d72cf7788fb0d17a99b4d4b26af49f767d2195/src/core_queue.ml#L283-L288 *)
let foldi coll ~init ~f =
  let i = ref 0 in
  fold coll ~init ~f:(fun acc a ->
    let acc = f !i acc a in
    i := !i + 1;
    acc
  )

let add_to_queue coll queue =
  match towards_list coll with
  | List ll | Both (_, ll) -> Queue.enqueue_all queue ll
  | Array arr -> Array.iter ~f:(Queue.enqueue queue) arr
  | Queue q -> Queue.iter ~f:(Queue.enqueue queue) q

let to_indexable coll =
  match coll.data with
  | List _ | Queue _ -> towards_queue coll
  | Array _ | Both _ -> towards_array coll

let make_stack coll =
  let i = ref 0 in
  let mut = ref [] in
  match to_indexable coll with
  | List ll ->
    mut := ll;
    fun () ->
      begin match !mut with
        | v::tail ->
          mut := tail;
          v
        | [] ->
          failwith "Collection: make_stack impossible case"
      end
  | Array arr | Both (arr, _) ->
    fun () ->
      let v = Array.get arr !i in
      incr i;
      v
  | Queue q ->
    fun () ->
      let v = Queue.get q !i in
      incr i;
      v

let two_lengths_check from coll_a coll_b =
  if Int.(=) (length coll_a) (length coll_b)
  then ()
  else
    failwith (
      sprintf
        "Collection: %s length mismatch: %d and %d"
        from (length coll_a) (length coll_b)
    )

let to_list_mapi_two coll_a coll_b ~f =
  two_lengths_check "to_list_mapi_two" coll_a coll_b;
  let next_b = make_stack coll_b in
  let j = ref 0 in
  to_list_map coll_a ~f:(fun x ->
    let k = !j in
    let result = f k x (next_b ()) in
    incr j;
    result
  )

let to_list_concat_mapi_two coll_a coll_b ~f =
  two_lengths_check "to_list_concat_mapi_two" coll_a coll_b;
  let next_b = make_stack coll_b in
  let j = ref 0 in
  to_list_concat_map coll_a ~f:(fun x ->
    let k = !j in
    let result = f k x (next_b ()) in
    incr j;
    result
  )

let concat_mapi_two coll_a coll_b ~f =
  two_lengths_check "concat_mapi_two" coll_a coll_b;
  let next_b = make_stack coll_b in
  let j = ref 0 in
  to_coll_concat_map coll_a ~f:(fun x ->
    let k = !j in
    let result = f k x (next_b ()) in
    incr j;
    result
  )

let concat_string ~sep coll =
  match apply_maps coll with
  | List ll -> String.concat ~sep ll
  | Array arr | Both (arr, _) -> String.concat_array ~sep arr
  | Queue q ->
    if Queue.is_empty q then "" else
    let len = Queue.length q in
    let buffer = Bigbuffer.create (len * (String.length sep) * 2) in
    for i = 0 to len - 2 do
      Bigbuffer.add_string buffer (Queue.get q i);
      Bigbuffer.add_string buffer sep;
    done;
    Bigbuffer.add_string buffer (Queue.get q (len - 1));
    Bigbuffer.contents buffer

let to_list_or_array coll =
  match apply_maps coll with
  | List ll -> `List ll
  | Array arr | Both (arr, _) -> `Array arr
  | Queue q -> `Array (Queue.to_array q)

let first coll =
  match apply_maps coll with
  | List ll -> List.hd ll
  | Array arr | Both (arr, _) ->
    Option.try_with (fun () -> Array.get arr 0)
  | Queue q ->
    Option.try_with (fun () -> Queue.get q 0)
