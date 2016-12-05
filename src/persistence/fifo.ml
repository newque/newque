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

let handler instance input messages =
  let open Zmq_obj_pb in
  let encoder = Pbrt.Encoder.create () in
  encode_input input encoder;
  let input = Pbrt.Encoder.to_bytes encoder in

  (* Register and send request *)
  let uid = Id.uuid_bytes () in
  let thread = Connector.submit instance.connector uid in
  let%lwt () = Lwt_zmq.Socket.send_all instance.socket (uid::input::messages) in

  (* Wait for response *)
  let%lwt frames = thread in

  (* Process response *)
  let%lwt (output, msgs_recv) as pair = match frames with
    | [] -> fail_with "No frames received"
    | head::msgs_recv ->
      let output = decode_output (Pbrt.Decoder.of_bytes head) in
      return (output, msgs_recv)
  in
  match output.errors with
  | [] -> return pair
  | errors -> fail (Exception.Multiple_exn errors)

let create ~chan_name host port =
  let outbound = sprintf "tcp://%s:%d" host port in
  let%lwt () = Logger.info (sprintf "Creating a new TCP socket on %s:%d" host port) in
  let router = ZMQ.Socket.create Zmq_tools.ctx ZMQ.Socket.dealer in
  (* TODO: ZMQ Options *)
  ZMQ.Socket.bind router outbound;
  let socket = Lwt_zmq.Socket.of_socket router in
  let connector = Connector.create 1.0 in

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
    let input = {
      channel = instance.chan_name;
      action = Write_input {
          atomic = None;
          ids = (Array.to_list ids);
        }
    }
    in
    let%lwt (output, _) = handler instance input (Array.to_list msgs) in
    match output.action with
    | Write_output write -> return (Option.value ~default:0 write.saved)
    | Error_output -> fail_with "Upstream returned Error_Output instead of Write_Output"
    | Read_output _ -> fail_with "Upstream returned Read_Output instead of Write_Output"
    | Count_output _ -> fail_with "Upstream returned Count_Output instead of Write_Output"
    | Delete_output -> fail_with "Upstream returned Delete_Output instead of Write_Output"
    | Health_output -> fail_with "Upstream returned Health_Output instead of Write_Output"

  let pull instance ~search ~fetch_last =
    let open Zmq_obj_pb in
    let (mode, limit) = Search.mode_and_limit search in
    let input = {
      channel = instance.chan_name;
      action = Read_input {
          mode = Mode.Read.to_string mode;
          limit = Some limit;
        }
    }
    in
    let%lwt (output, msgs) = handler instance input [] in
    match output.action with
    | Read_output read ->
      let arr_msgs = List.to_array msgs in
      if Int.(<>) read.length (Array.length arr_msgs)
      then async (fun () ->
          Logger.warning (sprintf "Lengths don't match: Read [%d] messages, but 'length' is %d" read.length (Array.length arr_msgs))
        );
      let meta = begin match read with
        | { last_id = Some l_id; last_timens = Some l_ts; } -> Some (l_id, l_ts)
        | _ -> None
      end
      in
      return (arr_msgs, None, meta)

    | Error_output -> fail_with "Upstream returned Error_Output instead of Read_Output"
    | Write_output _ -> fail_with "Upstream returned Write_Output instead of Read_Output"
    | Count_output _ -> fail_with "Upstream returned Count_Output instead of Read_Output"
    | Delete_output -> fail_with "Upstream returned Delete_Output instead of Read_Output"
    | Health_output -> fail_with "Upstream returned Health_Output instead of Read_Output"

  let size instance =
    let open Zmq_obj_pb in
    let input = {
      channel = instance.chan_name;
      action = Count_input;
    }
    in
    let%lwt (output, _) = handler instance input [] in
    match output.action with
    | Count_output count -> return (Option.value ~default:Int64.zero count.count)
    | Error_output -> fail_with "Upstream returned Error_Output instead of Count_Output"
    | Write_output _ -> fail_with "Upstream returned Write_Output instead of Count_Output"
    | Read_output _ -> fail_with "Upstream returned Read_Output instead of Count_Output"
    | Delete_output -> fail_with "Upstream returned Delete_Output instead of Count_Output"
    | Health_output -> fail_with "Upstream returned Health_Output instead of Count_Output"

  let delete instance =
    let open Zmq_obj_pb in
    let input = {
      channel = instance.chan_name;
      action = Delete_input;
    }
    in
    let%lwt (output, _) = handler instance input [] in
    match output.action with
    | Delete_output -> return_unit
    | Error_output -> fail_with "Upstream returned Error_Output instead of Delete_Output"
    | Write_output _ -> fail_with "Upstream returned Write_Output instead of Delete_Output"
    | Read_output _ -> fail_with "Upstream returned Read_Output instead of Delete_Output"
    | Count_output _ -> fail_with "Upstream returned Count_Output instead of Delete_Output"
    | Health_output -> fail_with "Upstream returned Health_Output instead of Delete_Output"

  let health instance =
    let open Zmq_obj_pb in
    let input = {
      channel = instance.chan_name;
      action = Health_input { global = false };
    }
    in
    let%lwt (output, _) = handler instance input [] in
    match output.action with
    | Health_output -> return []
    | Error_output -> fail_with "Upstream returned Error_Output instead of Health_Output"
    | Write_output _ -> fail_with "Upstream returned Write_Output instead of Health_Output"
    | Read_output _ -> fail_with "Upstream returned Read_Output instead of Health_Output"
    | Count_output _ -> fail_with "Upstream returned Count_Output instead of Health_Output"
    | Delete_output -> fail_with "Upstream returned Delete_Output instead of Health_Output"

end
