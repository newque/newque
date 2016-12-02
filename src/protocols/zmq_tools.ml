let ctx =
  let context = ZMQ.Context.create () in
  ZMQ.Context.set_io_threads context 1;
  context

let set_hwm sock receive send =
  ZMQ.Socket.set_receive_high_water_mark sock receive;
  ZMQ.Socket.set_send_high_water_mark sock send

let set_buffersize sock receive send =
  ZMQ.Socket.set_receive_buffer_size sock receive;
  ZMQ.Socket.set_send_buffer_size sock send

let set_timeout sock receive send =
  ZMQ.Socket.set_receive_timeout sock receive;
  ZMQ.Socket.set_send_timeout sock send
