open Core

(* http://api.zeromq.org/4-0:zmq-ctx-set *)
let ctx =
  let context = ZMQ.Context.create () in
  ZMQ.Context.set_io_threads context 2;
  ZMQ.Context.set_max_sockets context 5000;
  context

let start_delay = 1.0

let apply_default_settings socket =
  ZMQ.Socket.set_linger_period socket 60_000; (* One minute *)
  ZMQ.Socket.set_reconnect_interval_max socket 60_000; (* One minute *)
  ZMQ.Socket.set_send_high_water_mark socket 5_000;
  ZMQ.Socket.set_receive_high_water_mark socket 5_000

(* http://api.zeromq.org/4-0:zmq-setsockopt *)
let apply_settings socket conf =
  let open Config_t in
  Option.iter conf.zmq_maxmsgsize ~f:(ZMQ.Socket.set_max_message_size socket);
  Option.iter conf.zmq_linger ~f:(ZMQ.Socket.set_linger_period socket);
  Option.iter conf.zmq_reconnect_ivl ~f:(ZMQ.Socket.set_reconnect_interval socket);
  Option.iter conf.zmq_reconnect_ivl_max ~f:(ZMQ.Socket.set_reconnect_interval_max socket);
  Option.iter conf.zmq_backlog ~f:(ZMQ.Socket.set_connection_backlog socket);
  Option.iter conf.zmq_sndhwm ~f:(ZMQ.Socket.set_send_high_water_mark socket);
  Option.iter conf.zmq_rcvhwm ~f:(ZMQ.Socket.set_receive_high_water_mark socket)
