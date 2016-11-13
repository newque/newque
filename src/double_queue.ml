open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "DQ" end)

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

let get_data dq =
  let lefts = Queue.to_array dq.left in
  let rights = Queue.to_array dq.right in
  Queue.clear dq.left;
  Queue.clear dq.right;
  let old_wake = dq.wake in
  let () =
    let (thr, wake) = wait () in
    dq.thread <- thr;
    dq.wake <- wake
  in
  wakeup old_wake ();
  (lefts, rights)

let do_flush dq =
  try%lwt
    let (lefts, rights) = get_data dq in
    let%lwt _ = dq.handler lefts rights in
    return_unit
  with
  | err -> Logger.error (Exn.to_string err)

let create ~max_time ~max_size ~handler =
  let (thread, wake) = wait () in
  let dq = {
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
      if Float.(>) (Util.time_ms_float ()) (dq.last_flush +. dq.max_time)
      then do_flush dq
      else return_unit
    )
  );
  dq

let length dq = Queue.length dq.left

let check_max_size dq lefts =
  if (((length dq) + (Array.length lefts)) >= dq.max_size) && length dq > 0
  then do_flush dq
  else return_unit

let submit dq lefts rights =
  let old_thread = dq.thread in
  let%lwt () = check_max_size dq lefts rights in
  Array.iter ~f:(Queue.enqueue dq.left) lefts;
  Array.iter ~f:(Queue.enqueue dq.right);
  let%lwt () = check_max_size dq lefts in
  old_thread
