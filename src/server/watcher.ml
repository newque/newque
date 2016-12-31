open Core.Std
open Lwt

module Logger = Log.Make (struct let section = "Watcher" end)

type t = {
  router: Router.t;
  table: Listener.t Int.Table.t;
}

(* Listener by port *)
let create () = { table = Int.Table.create ~size:5 (); router = Router.create () }

let router watcher = watcher.router
let table watcher = watcher.table
let listeners watcher = Int.Table.data watcher.table

let listeners_to_json watcher port_opt =
  let convert_list port_listeners =
    let pairs = List.map port_listeners ~f:(fun (port, listener) ->
        let name = listener.Listener.id in
        let channels = match String.Table.find watcher.router.Router.table name with
          | None -> []
          | Some chan_table -> String.Table.keys chan_table
        in
        name, `Assoc [
          "protocol", `String (Listener.get_prot listener);
          "port", `Int port;
          "channels", `List (List.map channels ~f:(fun s -> `String s))
        ]
      )
    in
    `Assoc pairs
  in
  match port_opt with
  | Some port ->
    (* Only return that one *)
    begin match Int.Table.find watcher.table port with
      | None -> convert_list []
      | Some listener -> convert_list [port, listener]
    end
  | None ->
    (* Return all *)
    convert_list (Int.Table.to_alist watcher.table)

let channels_to_json watcher chan_name_opt =
  let convert_list channel_pairs =
    let pairs = List.map channel_pairs ~f:(fun (name, channel) ->
        name, (Channel.to_json channel)
      )
    in
    `Assoc pairs
  in
  match chan_name_opt with
  | Some chan_name ->
    (* Only return that one *)
    begin match Router.find_chan watcher.router ~listen_name:Listener.(private_listener.id) ~chan_name with
      | Ok chan -> return (convert_list [chan_name, chan])
      | Error errors -> fail (Exception.Multiple_exn errors)
    end
  | None ->
    (* Return all *)
    let%lwt channel_pairs = Router.all_channels watcher.router in
    return (convert_list channel_pairs)

(******
   Standard listeners
 ******)

let make_standard_routing watcher listen_name =
  let open Routing in
  (* Partially apply the routing function *)
  Standard {
    write_http = Router.write_http watcher.router ~listen_name;
    write_zmq = Router.write_zmq watcher.router ~listen_name;
    read_slice = Router.read_slice watcher.router ~listen_name;
    read_stream = Router.read_stream watcher.router ~listen_name;
    count = Router.count watcher.router ~listen_name;
    delete = Router.delete watcher.router ~listen_name;
    health = Router.health watcher.router ~listen_name;
  }

let start_http watcher generic specific =
  let open Config_t in
  let standard = make_standard_routing watcher generic.name in
  Http_prot.start generic specific standard

let start_zmq watcher generic specific =
  let open Config_t in
  let standard = make_standard_routing watcher generic.name in
  Zmq_prot.start generic specific standard

let rec monitor watcher listen =
  let open Listener in
  match listen.server with
  | Listener.HTTP (http, wakener) ->
    let open Http_prot in
    let must_restart = begin try%lwt
        let%lwt () = choose [http.thread; waiter_of_wakener wakener; waiter_of_wakener http.stop_w] in
        if not (is_sleeping http.thread) then return_true else return_false
      with
      | ex ->
        let%lwt () = Logger.error (Exception.full ex) in
        return_true
    end in
    begin match%lwt must_restart with
      | false -> return_unit (* Just stop monitoring it *)
      | true ->
        (* Restart the server and monitor it recursively *)
        let g = http.generic in
        let open Config_t in
        let%lwt () = Logger.notice (sprintf "Restarting HTTP listener [%s] on HTTP %s:%s" g.name g.host (Int.to_string g.port)) in
        let%lwt () = Http_prot.close http in
        let%lwt restarted = start_http watcher http.generic http.specific in
        let (_, new_wakener) = wait () in
        monitor watcher {id=listen.id; server=(HTTP (restarted, new_wakener))}
    end
  | Listener.ZMQ (zmq, wakener) -> return_unit
  | Private -> return_unit

let create_listeners watcher endpoints =
  let open Config_t in
  let open Listener in
  Lwt_list.iter_p (fun generic ->
    (* Stop and replace possible existing listener on the same port *)
    let%lwt () = match Int.Table.find_and_remove watcher.table generic.port with
      | Some { server = (HTTP (existing, _)); _ } -> Http_prot.stop existing
      | Some { server = (ZMQ (existing, _)); _ } -> Zmq_prot.stop existing
      | Some { server = Private }
      | None -> return_unit
    in
    (* Now start the new listeners *)
    let%lwt started = match generic.protocol_settings with
      | Config_http_prot specific ->
        let%lwt () = Logger.notice (sprintf "Starting [%s] on HTTP %s:%s" generic.name generic.host (Int.to_string generic.port)) in
        let%lwt http = start_http watcher generic specific in
        let (_, wakener) = wait () in
        return { id = generic.name; server=(HTTP (http, wakener)) }

      | Config_zmq_prot specific ->
        let%lwt () = Logger.notice (sprintf "Starting [%s] on ZMQ %s:%s" generic.name generic.host (Int.to_string generic.port)) in
        let%lwt zmq = start_zmq watcher generic specific in
        let (_, wakener) = wait () in
        return { id = generic.name; server= ZMQ (zmq, wakener); }
    in
    async (fun () -> monitor watcher started);
    Int.Table.add_exn watcher.table ~key:generic.port ~data:started;
    return_unit
  ) endpoints

(******
   Admin listener
 ******)

let make_admin_routing watcher =
  let open Routing in
  (* Partially apply the functions *)
  Admin {
    listeners_by_port = listeners_to_json watcher;
    channels_by_name = channels_to_json watcher;
  }

let create_admin_server watcher config =
  let open Config_t in
  let admin_spec_conf = {
    backlog = 5;
  } in
  let admin_conf = {
    name = "newque_admin";
    host = config.admin.a_host;
    port = config.admin.a_port;
    protocol_settings = Config_http_prot admin_spec_conf;
  } in
  let%lwt admin_server =
    let open Routing in
    Http_prot.start admin_conf admin_spec_conf (make_admin_routing watcher)
  in
  let (_, wakener) = wait () in
  let open Listener in
  async (fun () -> monitor watcher {id = admin_conf.name; server = HTTP (admin_server, wakener);});

  let success_str = sprintf "Started Admin server on HTTP %s:%d" admin_conf.host admin_conf.port in
  return (admin_server, success_str)
