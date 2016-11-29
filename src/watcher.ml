open Core.Std
open Lwt
open Listener

module Logger = Log.Make (struct let path = Log.outlog let section = "Watcher" end)

type t = {
  router: Router.t;
  table: Listener.t Int.Table.t;
}

(* Listener by port *)
let create () = { table = Int.Table.create ~size:5 (); router = Router.create () }

let router watcher = watcher.router
let table watcher = watcher.table
let listeners watcher = Int.Table.data watcher.table

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
  match listen.server with
  | Listener.HTTP (http, wakener) ->
    let open Http_prot in
    let must_restart = begin try%lwt
        let%lwt () = choose [http.thread; waiter_of_wakener wakener; waiter_of_wakener http.stop_w] in
        if not (is_sleeping http.thread) then return_true else return_false
      with
      | Unix.Unix_error (code, name, param) ->
        let%lwt () = Logger.error (Fs.format_unix_exn code name param) in
        return_true
      | ex ->
        let%lwt () = Logger.error (Exn.to_string ex) in
        return_true
    end in
    begin match%lwt must_restart with
      | false -> return_unit (* Just stop monitoring it *)
      | true ->
        (* Restart the server and monitor it recursively *)
        let g = http.generic in
        let open Config_t in
        let%lwt () = Logger.notice (sprintf "Restarting HTTP listener %s on HTTP %s:%s" g.name g.host (Int.to_string g.port)) in
        let%lwt () = Http_prot.close http in
        let%lwt restarted = start_http watcher http.generic http.specific in
        let (_, new_wakener) = wait () in
        monitor watcher {id=listen.id; server=(HTTP (restarted, new_wakener))}
    end
  | Listener.ZMQ (zmq, wakener) -> return_unit
  | Private -> return_unit

let create_listeners watcher endpoints =
  let open Config_t in
  Lwt_list.iter_p (fun generic ->
    (* Stop and replace possible existing listener on the same port *)
    let%lwt () = match Int.Table.find_and_remove watcher.table generic.port with
      | Some {server=(HTTP (existing, _));_} -> Http_prot.stop existing
      | Some {server=(ZMQ (existing, _));_} -> Zmq_prot.stop existing
      | Some {server=Private}
      | None -> return_unit
    in
    (* Now start the new listeners *)
    let%lwt started = match generic.protocol_settings with
      | Config_http_prot specific ->
        let%lwt () = Logger.notice (sprintf "Starting %s on HTTP %s:%s" generic.name generic.host (Int.to_string generic.port)) in
        let%lwt http = start_http watcher generic specific in
        let (_, wakener) = wait () in
        return {id=generic.name; server=(HTTP (http, wakener))}
      | Config_zmq_prot specific ->
        let%lwt () = Logger.notice (sprintf "Starting %s on ZMQ %s:%s" generic.name generic.host (Int.to_string generic.port)) in
        let%lwt zmq = start_zmq watcher generic specific in
        let (_, wakener) = wait () in
        return {id=generic.name; server=(ZMQ (zmq, wakener))}
    in
    async (fun () -> monitor watcher started);
    Int.Table.add_exn watcher.table ~key:generic.port ~data:started;
    return_unit
  ) endpoints
