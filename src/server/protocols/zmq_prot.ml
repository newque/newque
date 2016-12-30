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

let invalid_read_output = Zmq_obj_pb.({ length = 0; last_id = None; last_timens = None })

let handler zmq routing socket frames =
  let open Routing in
  (* let%lwt () = Logger.debug (String.concat ~sep:"--" frames) in *)
  let%lwt zmq = zmq in
  match frames with
  | header::id::meta::msgs ->
    let open Zmq_obj_pb in

    let%lwt (output, messages) = begin try%lwt
        let input = decode_input (Pbrt.Decoder.of_bytes meta) in
        let chan_name = input.channel in
        begin match input.action with

          | Write_input write ->
            let ids = Collection.of_list write.ids in
            let msgs = Collection.of_list msgs in
            let atomic = Option.value ~default:false write.atomic in
            let%lwt (errors, saved) =
              begin match%lwt routing.write_zmq ~chan_name ~ids ~msgs ~atomic with
                | Ok ((Some _) as count) -> return ([], count)
                | Ok None -> return ([], None)
                | Error errors -> return (errors, (Some 0))
              end
            in
            return ({ errors; action = Write_output { saved } }, Collection.empty)

          | Read_input read ->
            let%lwt (errors, read_output, messages) = begin match Mode.of_string read.mode with
              | Error str -> return ([str], invalid_read_output, Collection.empty)
              | Ok parsed_mode ->
                begin match Mode.wrap (parsed_mode :> Mode.Any.t) with
                  | `Read mode ->
                    begin match%lwt routing.read_slice ~chan_name ~mode ~limit:read.limit with
                      | Error errors -> return (errors, invalid_read_output, Collection.empty)
                      | Ok (slice, _) ->
                        let open Persistence in
                        let read_output = {
                          length = Collection.length slice.payloads;
                          last_id = Option.map slice.metadata ~f:(fun m -> m.last_id);
                          last_timens = Option.map slice.metadata ~f:(fun m -> m.last_timens);
                        }
                        in
                        return ([], read_output, slice.payloads)
                    end
                  | _ ->
                    return (
                      [sprintf "[%s] is not a valid Reading mode" (Mode.to_string (parsed_mode :> Mode.Any.t))],
                      invalid_read_output,
                      Collection.empty
                    )
                end
            end
            in
            return ({ errors; action = Read_output read_output }, messages)

          | Count_input ->
            let%lwt (errors, count) =
              begin match%lwt routing.count ~chan_name ~mode:`Count with
                | Ok count -> return ([], Some count)
                | Error errors -> return (errors, None)
              end
            in
            return ({ errors; action = Count_output { count } }, Collection.empty)

          | Delete_input ->
            let%lwt errors =
              begin match%lwt routing.delete ~chan_name ~mode:`Delete with
                | Ok () -> return []
                | Error errors -> return errors
              end
            in
            return ({ errors; action = Delete_output }, Collection.empty)

          | Health_input health ->
            let chan_name = if health.global then None else Some chan_name in
            let%lwt errors = routing.health ~chan_name ~mode:`Health in
            return ({ errors; action = Health_output }, Collection.empty)

        end
      with
      | ex ->
        let errors = Exception.human_list ex in
        return ({ errors; action = Error_output }, Collection.empty)
    end
    in
    let encoder = Pbrt.Encoder.create () in
    encode_output output encoder;
    let reply = Pbrt.Encoder.to_bytes encoder in
    Lwt_zmq.Socket.send_all socket (header::id::reply::(Collection.to_list messages |> snd))

  | strs ->
    let printable = Yojson.Basic.to_string (`List (List.map ~f:(fun s -> `String s) strs)) in
    let%lwt () = Logger.warning (sprintf "Received invalid msg parts on %s: %s" zmq.inbound printable) in
    let error =
      let open Zmq_obj_pb in
      let errors = [sprintf "Received invalid msg parts on %s. Expected [id], [input], [msgs...]." zmq.inbound] in
      let output = { errors; action = Error_output } in
      let encoder = Pbrt.Encoder.create () in
      encode_output output encoder;
      Pbrt.Encoder.to_bytes encoder
    in
    Lwt_zmq.Socket.send_all socket (error::strs)

let start generic specific routing =
  let open Config_t in
  let open Routing in
  let inproc = sprintf "inproc://%s" generic.name in
  let inbound = sprintf "tcp://%s:%d" generic.host generic.port in
  let (instance_t, instance_w) = wait () in
  let (stop_t, stop_w) = wait () in

  let%lwt () = Logger.info (sprintf "Creating a new TCP socket on %s:%d" generic.host generic.port) in
  let frontend = ZMQ.Socket.create Zmq_tools.ctx ZMQ.Socket.router in
  Zmq_tools.set_hwm frontend specific.receive_hwm specific.send_hwm;
  ZMQ.Socket.bind frontend inbound;
  let backend = ZMQ.Socket.create Zmq_tools.ctx ZMQ.Socket.dealer in
  ZMQ.Socket.bind backend inproc;

  let proxy = Lwt_preemptive.detach (fun () ->
      ZMQ.Proxy.create frontend backend;
    ) ()
  in
  async (fun () -> pick [stop_t; proxy]);

  (* TODO: Configurable timeout for disconnected clients *)

  let%lwt callback = match routing with
    | Admin _ -> fail_with "ZMQ listeners don't support Admin routing"
    | Standard standard_routing -> return (handler instance_t standard_routing)
  in

  let workers = Array.init specific.concurrency (fun _ ->
      let sock = ZMQ.Socket.create Zmq_tools.ctx ZMQ.Socket.dealer in
      ZMQ.Socket.connect sock inproc;
      let socket = Lwt_zmq.Socket.of_socket sock in
      let rec loop socket =
        let%lwt () = try%lwt
            let%lwt frames = Lwt_zmq.Socket.recv_all socket in
            callback socket frames
          with
          | ex -> Logger.error (Exception.full ex)
        in
        loop socket
      in
      let accept =
        let%lwt () = Lwt_unix.sleep Zmq_tools.start_delay in
        loop socket
      in
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
