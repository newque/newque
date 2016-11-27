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

let handler zmq routing socket frames =
  let open Routing in
  let%lwt zmq = zmq in
  match frames with
  | header::id::meta::msgs ->
    let open Zmq_obj_pb in

    let input = decode_input (Pbrt.Decoder.of_bytes meta) in
    let%lwt reply = begin match input.action with
      | Write write ->
        let ids = Array.of_list write.ids in
        let msgs = Array.of_list msgs in
        let%lwt (errors, saved) = begin match%lwt routing.write_zmq ~chan_name:input.channel ~ids ~msgs ~atomic:write.atomic with
          | Ok ((Some _) as count) -> return ([], count)
          | Ok None -> return ([], None)
          | Error errors -> return (errors, (Some 0))
        end
        in
        let response = { errors; saved; } in
        let encoder = Pbrt.Encoder.create () in
        encode_write response encoder;
        return (Pbrt.Encoder.to_bytes encoder)
      | Count _ -> return "UNIMPLEMENTED: ZMQ COUNT"
    end
    in

    print_endline reply;

    let%lwt () = Lwt_zmq.Socket.send socket ~more:true header in
    let%lwt () = Lwt_zmq.Socket.send socket ~more:true id in
    let%lwt () = Lwt_zmq.Socket.send socket ~more:true reply in
    let%lwt () = Lwt_zmq.Socket.send socket ~more:false "We are done" in

    return_unit
  | strs ->
    let printable = Yojson.Basic.to_string (`List (List.map ~f:(fun s -> `String s) strs)) in
    let%lwt () = Logger.warning (Printf.sprintf "Received invalid msg parts on %s: %s" zmq.inproc printable) in
    (* TODO: Return a decent error *)
    Lwt_zmq.Socket.send_all socket strs

let set_hwm sock receive send =
  ZMQ.Socket.set_receive_high_water_mark sock receive;
  ZMQ.Socket.set_send_high_water_mark sock send

let start generic specific routing =
  let open Config_t in
  let open Routing in
  let inproc = Printf.sprintf "inproc://%s" generic.name in
  let inbound = Printf.sprintf "tcp://%s:%d" generic.host generic.port in
  let (instance_t, instance_w) = wait () in
  let (stop_t, stop_w) = wait () in

  let frontend = ZMQ.Socket.create ctx ZMQ.Socket.router in
  ZMQ.Socket.bind frontend inbound;
  set_hwm frontend specific.receive_hwm specific.send_hwm;
  let backend = ZMQ.Socket.create ctx ZMQ.Socket.dealer in
  ZMQ.Socket.bind backend inproc;

  let proxy = Lwt_preemptive.detach (fun () ->
      ZMQ.Proxy.create frontend backend;
    ) ()
  in
  async (fun () -> pick [stop_t; proxy]);

  (* TODO: Reuse Encoder? *)

  (* TODO: Configurable timeout for disconnected clients *)
  (* print_endline (sprintf "send timeout %d" (ZMQ.Socket.get_send_timeout frontend)); *)
  (* print_endline (sprintf "receive timeout %d" (ZMQ.Socket.get_receive_timeout frontend)); *)

  let%lwt callback = match routing with
    | Admin _ -> fail_with "ZMQ listeners don't support Admin routing"
    | Standard standard_routing -> return (handler instance_t standard_routing)
  in

  let workers = Array.init specific.concurrency (fun _ ->
      let sock = ZMQ.Socket.create ctx ZMQ.Socket.dealer in
      ZMQ.Socket.connect sock inproc;
      let socket = Lwt_zmq.Socket.of_socket sock in
      let rec loop socket =
        let%lwt frames = Lwt_zmq.Socket.recv_all socket in
        let%lwt () = callback socket frames in
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
