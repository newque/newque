open Core.Std
open Lwt

type ('a, 'b, 'c) t = {
  mutable lefts: 'a Queue.t;
  mutable rights: 'b Queue.t;
  max_time: float; (* milliseconds *)
  max_size: int;
  handler: 'a Collection.t -> 'b Collection.t -> 'c Lwt.t;
  mutable thread: 'c Lwt.t;
  mutable wake: 'c Lwt.u;
  mutable last_flush: float;
}

let get_data batcher =
  let lefts = Collection.of_queue batcher.lefts in
  let rights = Collection.of_queue batcher.rights in
  batcher.lefts <- Queue.create ~capacity:batcher.max_size ();
  batcher.rights <- Queue.create ~capacity:batcher.max_size ();
  (lefts, rights)

let do_flush batcher =
  let (lefts, rights) = get_data batcher in
  batcher.last_flush <- Util.time_ms_float ();
  let%lwt () = try%lwt
      let%lwt saved = batcher.handler lefts rights in
      wakeup batcher.wake saved;
      return_unit
    with
    | err ->
      wakeup_exn batcher.wake err;
      return_unit
  in
  let () =
    let (thr, wake) = wait () in
    batcher.thread <- thr;
    batcher.wake <- wake
  in
  return_unit

let length batcher = Queue.length batcher.lefts

let create ~max_time ~max_size ~handler =
  let (thread, wake) = wait () in
  let batcher = {
    lefts = Queue.create ~capacity:max_size ();
    rights = Queue.create ~capacity:max_size ();
    max_time;
    max_size;
    handler;
    thread;
    wake;
    last_flush = Util.time_ms_float ();
  }
  in
  async (
    Util.make_interval (max_time /. 1000.) (fun () ->
      if Float.(>) (Util.time_ms_float ()) (batcher.last_flush +. batcher.max_time)
      && Int.is_positive (length batcher)
      then do_flush batcher
      else return_unit
    )
  );
  batcher

let discard thread =
  let%lwt _ = thread in
  return_unit

let submit batcher left_arr right_arr =
  let threads = Collection.to_list_concat_mapi_two left_arr right_arr ~f:(fun i left right ->
      Queue.enqueue batcher.lefts left;
      Queue.enqueue batcher.rights right;
      if (Int.(=) (length batcher) batcher.max_size)
      then
        let bound = discard batcher.thread in
        ignore (do_flush batcher);
        [bound]
      else []
    )
                |> snd
  in
  let threads = if List.is_empty threads then [discard batcher.thread] else threads in
  join threads
