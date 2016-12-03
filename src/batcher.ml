open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Batcher" end)

type ('a, 'b) t = {
  lefts: 'a Queue.t;
  rights: 'b Queue.t;
  max_time: float; (* milliseconds *)
  max_size: int;
  handler: 'a array -> 'b array -> int Lwt.t;
  mutable thread: unit Lwt.t sexp_opaque;
  mutable wake: unit Lwt.u sexp_opaque;
  mutable last_flush: float;
} [@@deriving sexp]

let get_data batcher =
  let lefts = Queue.to_array batcher.lefts in
  let rights = Queue.to_array batcher.rights in
  Queue.clear batcher.lefts;
  Queue.clear batcher.rights;
  (lefts, rights)

let do_flush batcher =
  let (lefts, rights) = get_data batcher in
  try%lwt
    batcher.last_flush <- Util.time_ms_float ();
    let%lwt _ = batcher.handler lefts rights in
    let old_wake = batcher.wake in
    let () =
      let (thr, wake) = wait () in
      batcher.thread <- thr;
      batcher.wake <- wake
    in
    wakeup old_wake ();
    return_unit
  with
  | err -> Logger.error (Exn.to_string err)

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

let check_max_size batcher =
  if (Int.(=) (succ (length batcher)) batcher.max_size)
  then do_flush batcher
  else batcher.thread

let submit batcher left right =
  Queue.enqueue batcher.lefts left;
  Queue.enqueue batcher.rights right;
  check_max_size batcher
