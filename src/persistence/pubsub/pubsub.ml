open Core
open Lwt

module Logger = Log.Make (struct let section = "Pubsub" end)

type pubsub_t = {
  chan_name: string;
  host: string;
  port: int;
  outbound: string;
  pub: [`Pub] ZMQ.Socket.t;
  socket: [`Pub] Lwt_zmq.Socket.t;
}

let create ~chan_name ~host ~port ~socket_settings =
  let outbound = sprintf "tcp://%s:%d" host port in
  let%lwt () = Logger.info (sprintf "Creating a new TCP socket on %s:%d" host port) in

  let pub = ZMQ.Socket.create Zmq_tools.ctx ZMQ.Socket.pub in
  Zmq_tools.apply_default_settings pub;
  Option.iter socket_settings ~f:(Zmq_tools.apply_settings pub);

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

  type t = pubsub_t

  let close instance =
    wrap (fun () ->
      ZMQ.Socket.unbind instance.pub instance.outbound;
      ZMQ.Socket.close instance.pub
    )

  let push instance ~msgs ~ids =
    let open Zmq_obj_types in
    let open Zmq_obj_pb in
    let input = { channel = instance.chan_name; action = Write_input { atomic = None; ids = (Collection.to_list ids |> snd); } } in
    let encoder = Pbrt.Encoder.create () in
    encode_input input encoder;
    let input = Pbrt.Encoder.to_bytes encoder in
    let%lwt () = Lwt_zmq.Socket.send_all instance.socket (input::(Collection.to_list msgs |> snd)) in
    return (Collection.length msgs)

  let pull instance ~search ~fetch_last = fail_with "Invalid operation: Pubsub read"

  let size instance = fail_with "Invalid operation: Pubsub size"

  let delete instance = fail_with "Invalid operation: Pubsub count"

  let health instance =
    match Util.parse_sync ZMQ.Socket.get_fd instance.pub with
    | Ok _ -> return []
    | Error err -> return [err]

end
