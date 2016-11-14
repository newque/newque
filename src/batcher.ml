open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Batcher" end)

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

let get_data batcher =
  let lefts = Queue.to_array batcher.left in
  let rights = Queue.to_array batcher.right in
  Queue.clear batcher.left;
  Queue.clear batcher.right;
  let old_wake = batcher.wake in
  let () =
    let (thr, wake) = wait () in
    batcher.thread <- thr;
    batcher.wake <- wake
  in
  wakeup old_wake ();
  (lefts, rights)

let do_flush batcher =
  try%lwt
    let (lefts, rights) = get_data batcher in
    let%lwt _ = batcher.handler lefts rights in
    return_unit
  with
  | err -> Logger.error (Exn.to_string err)

let create ~max_time ~max_size ~handler =
  let (thread, wake) = wait () in
  let batcher = {
    left = Queue.create ~capacity:max_size ();
    right = Queue.create ~capacity:max_size ();
    max_time;
    max_size;
    handler;
    thread;
    wake;
    last_flush = Util.time_ms_float ();
  }
  in
  (* Background timer *)
  async (fun () ->
    Util.make_interval (max_time /. 1000.) (fun () ->
      if Float.(>) (Util.time_ms_float ()) (batcher.last_flush +. batcher.max_time)
      then do_flush batcher
      else return_unit
    )
  );
  batcher

let length batcher = Queue.length batcher.left

let check_max_size batcher lefts =
  if (((length batcher) + (Array.length lefts)) >= batcher.max_size) && length batcher > 0
  then do_flush batcher
  else return_unit

let submit batcher lefts rights =
  let old_thread = batcher.thread in
  let%lwt () = check_max_size batcher lefts in
  Array.iter ~f:(Queue.enqueue batcher.left) lefts;
  Array.iter ~f:(Queue.enqueue batcher.right) rights;
  let%lwt () = check_max_size batcher lefts in
  old_thread
