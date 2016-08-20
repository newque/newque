open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

module Logger = Log.Make (struct let path = Log.outlog end)

type t = {
  generic: Config_t.config_listener;
  specific: Config_t.config_http_settings;
  sock: Lwt_unix.file_descr;
  mutable filter: (Server.conn -> Request.t -> Cohttp_lwt_body.t -> (unit, string) Result.t Lwt.t);
  close: unit Lwt.u;
  ctx: Cohttp_lwt_unix_net.ctx;
  thread: unit Lwt.t;
}

let default_filter _ _ _ = return (Error "Listener not ready")

let callback http route_single route_batch ((ch, _) as conn) req body =
  let%lwt http = http in
  match%lwt http.filter conn req body with
  | Error str ->
    let body = str in
    let status = Code.status_of_code 400 in
    Server.respond_string ~status ~body ()
  | Ok () ->
    let%lwt body = Cohttp_lwt_body.to_string body in
    let status = Code.status_of_code 200 in
    Server.respond_string ~status ~body ()

let open_sockets = Int.Table.create ~size:5 ()

let healthy_socket sock =
  try%lwt
    Lwt_unix.check_descriptor sock;
    return_true
  with
  | ex -> return_false

let make_socket ~backlog host port =
  let open Lwt_unix in
  let%lwt info = Lwt_unix.getaddrinfo host "0" [AI_PASSIVE; AI_SOCKTYPE SOCK_STREAM] in
  let sockaddr, ip = match List.hd info with
    | Some {ai_addr = (ADDR_UNIX _)} -> failwith "Cant listen to TCP on a domain socket"
    | Some {ai_addr = (ADDR_INET (a,_))} -> ADDR_INET (a,port), Ipaddr_unix.of_inet_addr a
    | None -> ADDR_INET (Unix.Inet_addr.bind_any,port), Ipaddr.(V4 V4.any)
  in
  let sock = Lwt_unix.socket (Unix.domain_of_sockaddr sockaddr)
      Unix.SOCK_STREAM 0 in
  Lwt_unix.setsockopt sock SO_REUSEADDR true;
  Lwt_unix.bind sock sockaddr;
  Lwt_unix.listen sock backlog;
  Lwt_unix.set_close_on_exec sock;
  return sock

let start generic specific route_single route_batch =
  let open Config_t in
  let%lwt sock = match Int.Table.find_and_remove open_sockets generic.port with
    | Some s ->
      begin match%lwt healthy_socket s with
        | true -> return s
        | false -> make_socket ~backlog:specific.backlog generic.host generic.port
      end
    | None -> make_socket ~backlog:specific.backlog generic.host generic.port
  in
  let%lwt ctx = Conduit_lwt_unix.init () in
  let ctx = Cohttp_lwt_unix_net.init ~ctx () in
  let mode = `TCP (`Socket sock) in
  let (instance_t, instance_w) = wait () in
  let conf = Server.make ~callback:(callback instance_t route_single route_batch) () in
  let (stop, close) = wait () in
  let thread = Server.create ~stop ~ctx ~mode conf in
  let instance = {generic; specific; sock; filter=default_filter; close; ctx; thread;} in
  wakeup instance_w instance;
  return instance

let stop http =
  let open Config_t in
  wakeup http.close ();
  let%lwt () = waiter_of_wakener http.close in
  Int.Table.add_exn open_sockets ~key:http.generic.port ~data:http.sock;
  return_unit

let close http =
  let open Config_t in
  let%lwt () = stop http in
  match Int.Table.find_and_remove open_sockets http.generic.port with
  | Some s -> Lwt_unix.close s
  | None -> return_unit
