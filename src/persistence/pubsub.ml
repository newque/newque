open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Pubsub" end)

type pubsub_t = {
  chan_name: string;
  host: string;
  port: int;
  outbound: string;
  pub: [`Pub] ZMQ.Socket.t sexp_opaque;
  socket: [`Pub] Lwt_zmq.Socket.t sexp_opaque;
} [@@deriving sexp]

let create ~chan_name host port =
  let outbound = sprintf "tcp://%s:%d" host port in
  let%lwt () = Logger.info (sprintf "Creating a new TCP socket on %s:%d" host port) in
  let pub = ZMQ.Socket.create Zmq_tools.ctx ZMQ.Socket.pub in
  (* TODO: ZMQ Options *)
  ZMQ.Socket.bind pub outbound;
  let socket = Lwt_zmq.Socket.of_socket pub in

  let instance = {
    chan_name;
    host;
    port;
    outbound;
    pub;
    socket;
  }
  in
  return instance

module M = struct

  type t = pubsub_t [@@deriving sexp]

  let close instance =
    wrap (fun () ->
      ZMQ.Socket.unbind instance.pub instance.outbound;
      ZMQ.Socket.close instance.pub
    )

  let push instance ~msgs ~ids =
    let open Zmq_obj_pb in
    let input = { channel = instance.chan_name; action = Write_input { atomic = None; ids = (Array.to_list ids); } } in
    let encoder = Pbrt.Encoder.create () in
    encode_input input encoder;
    let input = Pbrt.Encoder.to_bytes encoder in
    let%lwt () = Lwt_zmq.Socket.send_all instance.socket (input::(Array.to_list msgs)) in
    return (Array.length msgs)

  let pull instance ~search ~fetch_last = fail_with "Invalid operation: Pubsub read"

  let size instance = fail_with "Invalid operation: Pubsub size"

  let delete instance = fail_with "Invalid operation: Pubsub count"

  let health instance =
    match Util.parse_sync ZMQ.Socket.get_fd instance.pub with
    | Ok _ -> return []
    | Error err -> return [err]

end
