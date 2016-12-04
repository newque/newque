open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Fifo" end)

type fifo_t = {
  chan_name: string;
  host: string;
  port: int;
  outbound: string;
  router: [`Dealer] ZMQ.Socket.t sexp_opaque;
  socket: [`Dealer] Lwt_zmq.Socket.t sexp_opaque;
  connector: string list Connector.t;
  workers: unit Lwt.t array sexp_opaque;
} [@@deriving sexp]

let create ~chan_name host port =
  let outbound = sprintf "tcp://%s:%d" host port in
  let%lwt () = Logger.info (sprintf "Creating a new TCP socket on %s:%d" host port) in
  let router = ZMQ.Socket.create Zmq_tools.ctx ZMQ.Socket.dealer in
  (* TODO: ZMQ Options *)
  ZMQ.Socket.bind router outbound;
  let socket = Lwt_zmq.Socket.of_socket router in
  let connector = Connector.create 3.0 in

  let workers = Array.init 5 (fun _ ->
      let open Zmq_obj_pb in
      let rec loop socket =
        let%lwt () = try%lwt
            match%lwt Lwt_zmq.Socket.recv_all socket with
            | [] -> fail_with "No frames received"
            | uid::frames ->
              Connector.resolve connector uid frames
          with ex ->
            let str = match ex with
              | Failure str -> str
              | ex -> Exn.to_string ex
            in
            Logger.error (sprintf "Error on channel [%s]: %s" chan_name str)
        in
        loop socket
      in
      let accept =
        let%lwt () = Lwt_unix.sleep Zmq_tools.start_delay in
        loop socket
      in
      async (fun () -> accept);
      accept
    )
  in

  let instance = {
    chan_name;
    host;
    port;
    outbound;
    router;
    socket;
    connector;
    workers;
  }
  in
  return instance

module M = struct

  type t = fifo_t [@@deriving sexp]

  let close instance =
    (* TODO: Close workers *)
    wrap (fun () ->
      ZMQ.Socket.unbind instance.router instance.outbound;
      ZMQ.Socket.close instance.router
    )

  let push instance ~msgs ~ids =
    let open Zmq_obj_pb in

    (* Build request *)
    let input = { channel = instance.chan_name; action = Write_input { atomic = None; ids = (Array.to_list ids); } } in
    let encoder = Pbrt.Encoder.create () in
    encode_input input encoder;
    let input = Pbrt.Encoder.to_bytes encoder in

    (* Register and send request *)
    let uid = Id.uuid_bytes () in
    let thread = Connector.submit instance.connector uid in
    let%lwt () = Lwt_zmq.Socket.send_all instance.socket (uid::input::(Array.to_list msgs)) in

    (* Wait for response *)
    let%lwt frames = thread in

    (* Process response *)
    let output = decode_output (Pbrt.Decoder.of_bytes (List.hd_exn frames)) in
    match output.errors with
    | [] ->
      begin match output.action with
        | Write_output write -> return (Option.value ~default:0 write.saved)
        | Error_output -> fail_with "Upstream returned Error_Output instead of Write_Output"
        | Read_output _ -> fail_with "Upstream returned Read_Output instead of Write_Output"
        | Count_output _ -> fail_with "Upstream returned Count_Output instead of Write_Output"
        | Delete_output -> fail_with "Upstream returned Delete_Output instead of Write_Output"
        | Health_output -> fail_with "Upstream returned Health_Output instead of Write_Output"
      end
    | errors -> fail (Exception.Multiple_exn errors)

  let pull instance ~search ~fetch_last = fail_with "Unimplemented: Fifo pull"

  let size instance = fail_with "Unimplemented: Fifo size"

  let delete instance = fail_with "Unimplemented: Fifo delete"

  let health instance =
    (* TODO *)
    return []

end
