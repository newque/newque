open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Zmq" end)

type worker = {
  accept: unit Lwt.t;
  socket: [`Dealer] Lwt_zmq.Socket.t;
}

type t = {
  generic : Config_t.config_listener;
  specific : Config_t.config_zmq_settings;
  inproc: string;
  inbound: string;
  frontend: [`Router] ZMQ.Socket.t;
  backend: [`Dealer] ZMQ.Socket.t;
  workers: worker array;
  proxy: unit Lwt.t;
  stop_w: unit Lwt.u;
  ctx: ZMQ.Context.t;
}
let sexp_of_t zmq =
  let open Config_t in
  Sexp.List [
    Sexp.List [
      Sexp.Atom zmq.generic.name;
      Sexp.Atom zmq.generic.host;
      Sexp.Atom (Int.to_string zmq.generic.port);
    ];
    Sexp.List [
      Sexp.Atom (Int.to_string zmq.specific.concurrency);
    ];
  ]

let ctx = ZMQ.Context.create ()
let () = ZMQ.Context.set_io_threads ctx 1

let handler zmq routing conn req body = return_unit

let start generic specific routing =
  let open Config_t in
  let open Routing in
  let inproc = Printf.sprintf "inproc://%s" generic.name in
  let inbound = Printf.sprintf "tcp://%s:%d" generic.host generic.port in
  let (instance_t, instance_w) = wait () in
  let (stop_t, stop_w) = wait () in

  let frontend = ZMQ.Socket.create ctx ZMQ.Socket.router in
  ZMQ.Socket.bind frontend inbound;
  let backend = ZMQ.Socket.create ctx ZMQ.Socket.dealer in
  ZMQ.Socket.bind backend inproc;
  let proxy = Lwt_preemptive.detach (fun () ->
      ZMQ.Proxy.create frontend backend;
    ) ()
  in
  async (fun () -> pick [stop_t; proxy]);

  let workers = Array.init specific.concurrency (fun _ ->
      let sock = ZMQ.Socket.create ctx ZMQ.Socket.dealer in
      ZMQ.Socket.connect sock inproc;
      let socket = Lwt_zmq.Socket.of_socket sock in
      let rec loop socket =
        let%lwt frames = match%lwt Lwt_zmq.Socket.recv_all socket with
          | [header; id; msg] -> return (Ok ([header; id], msg))
          | [header; msg] -> return (Ok ([header], msg))
          | strs ->
            let printable = Yojson.Basic.to_string (`List (List.map ~f:(fun s -> `String s) strs)) in
            let%lwt () = Logger.warning (Printf.sprintf "Received invalid msg parts on %s: %s" inproc printable) in
            return (Result.Error strs)
        in
        let%lwt () = match frames with
          | Error strs -> Lwt_zmq.Socket.send_all socket strs
          | Ok (headers, msg) ->
            let reply = Printf.sprintf "__Hello %s!__" msg in
            print_endline reply;
            let%lwt () = Lwt_unix.sleep 2.0 in
            let%lwt () = Lwt_zmq.Socket.send_all socket (headers @ [reply]) in
            return_unit
        in
        loop socket
      in
      let accept = loop socket in
      async (fun () -> accept);
      { socket; accept; }
    )
  in
  let instance = {
    generic;
    specific;
    inproc;
    inbound;
    frontend;
    backend;
    workers;
    proxy;
    stop_w;
    ctx;
  }
  in
  wakeup instance_w instance;
  return instance

let stop zmq =
  Array.iter zmq.workers ~f:(fun worker ->
    cancel worker.accept
  );
  return_unit

let close zmq =
  let%lwt () = stop zmq in
  if is_sleeping (waiter_of_wakener zmq.stop_w) then wakeup zmq.stop_w ();
  ZMQ.Socket.unbind zmq.frontend zmq.inbound;
  ZMQ.Socket.unbind zmq.backend zmq.inproc;
  ZMQ.Socket.close zmq.frontend;
  ZMQ.Socket.close zmq.backend;
  Array.iter zmq.workers ~f:(fun worker ->
    let sock = Lwt_zmq.Socket.to_socket worker.socket in
    ZMQ.Socket.disconnect sock zmq.inproc;
    ZMQ.Socket.close sock
  );
  return_unit
