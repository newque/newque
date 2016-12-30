open Core.Std
open Lwt
open Zmq_obj_pb

module Logger = Log.Make (struct let path = Log.outlog let section = "Fifo" end)

type fifo_t = {
  chan_name: string;
  host: string;
  port: int;
  timeout: float; (* in seconds *)
  health_time_limit: float; (* in seconds *)
  outbound: string;
  router: [`Dealer] ZMQ.Socket.t sexp_opaque;
  socket: [`Dealer] Lwt_zmq.Socket.t sexp_opaque;
  connector: string list Connector.t;
  workers: unit Lwt.t array sexp_opaque;
} [@@deriving sexp]

type _ action =
  | Write_action : output_write_output action
  | Read_action : output_read_output action
  | Count_action : output_count_output action
  | Error_action : unit action
  | Delete_action : unit action
  | Health_action : unit action

let unwrap_action : type a. output_action -> a action -> string -> a Lwt.t =
  fun received desired desired_name ->
    let get_name r = match r with
      | Write_output _ -> "Write_Output"
      | Read_output _ -> "Read_Output"
      | Count_output _ -> "Count_Output"
      | Error_output -> "Error_Output"
      | Delete_output -> "Delete_Output"
      | Health_output -> "Health_Output"
    in
    match (desired, received) with
    | (Write_action, Write_output x) -> return x
    | (Read_action, Read_output x) -> return x
    | (Count_action, Count_output x) -> return x
    | (Error_action, Error_output) -> return_unit
    | (Delete_action, Delete_output) -> return_unit
    | (Health_action, Health_output) -> return_unit
    | (_, output) -> fail_with (sprintf "Upstream returned %s instead of %s" (get_name output) desired_name)

let handler instance input messages =
  let encoder = Pbrt.Encoder.create () in
  encode_input input encoder;
  let input = Pbrt.Encoder.to_bytes encoder in

  (* Register and send request *)
  let uid = Id.uuid_bytes () in
  let thunk = Connector.submit instance.connector uid instance.outbound in
  let%lwt () = Lwt_zmq.Socket.send_all instance.socket (uid::input::messages) in

  (* Wait for response *)
  let%lwt frames = thunk () in

  (* Process response *)
  let%lwt (output, msgs_recv) as pair = match frames with
    | [] -> fail_with "No frames received"
    | head::msgs_recv ->
      wrap2 (fun head msgs_recv ->
        let output = decode_output (Pbrt.Decoder.of_bytes head) in
        (output, msgs_recv)
      ) head msgs_recv
  in
  match output.errors with
  | [] -> return pair
  | errors -> fail (Exception.Multiple_exn errors)

let create ~chan_name ~host ~port ~timeout_ms ~health_time_limit_ms =
  let outbound = sprintf "tcp://%s:%d" host port in
  let%lwt () = Logger.info (sprintf "Creating a new TCP socket on %s:%d" host port) in
  let timeout = Float.(/) timeout_ms 1000. in
  let router = ZMQ.Socket.create Zmq_tools.ctx ZMQ.Socket.dealer in
  (* TODO: ZMQ Options *)
  ZMQ.Socket.bind router outbound;
  let socket = Lwt_zmq.Socket.of_socket router in
  let connector = Connector.create timeout in

  let workers = Array.init 5 (fun _ ->
      let rec loop socket =
        let%lwt () = try%lwt
            match%lwt Lwt_zmq.Socket.recv_all socket with
            | [] -> fail_with "No frames received"
            | uid::frames ->
              Connector.resolve connector uid frames
          with ex ->
            Logger.error (sprintf "Error on channel [%s]: %s" chan_name (Exception.full ex))
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
    timeout;
    health_time_limit = Float.(/) health_time_limit_ms 1000.;
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
    let input = {
      channel = instance.chan_name;
      action = Write_input {
          atomic = None;
          ids = (Collection.to_list ids |> snd);
        }
    }
    in
    let%lwt (output, _) = handler instance input (Collection.to_list msgs |> snd) in
    let%lwt write = unwrap_action output.action Write_action "Write_Output" in
    return (Option.value ~default:0 write.saved)

  let pull instance ~search ~fetch_last =
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
    let%lwt read = unwrap_action output.action Read_action "Read_Output" in
    let coll_msgs = Collection.of_list msgs in
    if Int.(<>) read.length (Collection.length coll_msgs)
    then async (fun () ->
        Logger.warning (sprintf "Lengths don't match: Read [%d] messages, but 'length' is [%d]" read.length (Collection.length coll_msgs))
      );
    let meta = begin match read with
      | { last_id = Some l_id; last_timens = Some l_ts; } -> Some (l_id, l_ts)
      | _ -> None
    end
    in
    return (coll_msgs, None, meta)

  let size instance =
    let input = {
      channel = instance.chan_name;
      action = Count_input;
    }
    in
    let%lwt (output, _) = handler instance input [] in
    let%lwt count = unwrap_action output.action Count_action "Count_Output" in
    return (Option.value ~default:Int64.zero count.count)

  let delete instance =
    let%lwt () = Logger.info (sprintf "Deleting data in [%s]" instance.chan_name) in
    let input = {
      channel = instance.chan_name;
      action = Delete_input;
    }
    in
    let%lwt (output, _) = handler instance input [] in
    unwrap_action output.action Delete_action "Delete_Output"

  let health instance =
    (* The connector has its own timeout and fails with Failure.
       If no consumer reads or answers within time_limit, we consider
       the health check as passed. *)
    let time_limit = instance.health_time_limit in
    let thread =
      let input = {
        channel = instance.chan_name;
        action = Health_input { global = false };
      }
      in
      let%lwt (output, _) = handler instance input [] in
      let%lwt () = unwrap_action output.action Health_action "Health_Output" in
      return []
    in
    try%lwt
      pick [thread; Lwt_unix.timeout time_limit]
    with
    | Lwt_unix.Timeout ->
      let%lwt () = Logger.warning (sprintf
            "Channel [%s]: No consumer read or answered health check within %f seconds. OK by default."
            instance.chan_name time_limit
        )
      in
      return []

end
