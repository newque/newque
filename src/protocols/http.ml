open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

module Logger = Log.Make (struct let path = Log.outlog end)

type t = {
  port: int;
  sock: Lwt_unix.file_descr;
  close: unit Lwt.u;
  ctx: Cohttp_lwt_unix_net.ctx;
  thread: unit Lwt.t;
}

let open_sockets : Lwt_unix.file_descr Int.Table.t = Int.Table.create ~size:5 ()

let make_socket host port =
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
  Lwt_unix.listen sock 15;
  Lwt_unix.set_close_on_exec sock;
  return sock


let start generic http =
  let callback conn req body =
    let status = Code.status_of_code 201 in
    Server.respond_string ~status ~body:"Hello world!!" ()
  in
  let open Config_j in
  let%lwt () = match Int.Table.find_and_remove open_sockets generic.port with
    | Some s -> Lwt_unix.close s
    | None -> return_unit
  in
  let%lwt sock = make_socket generic.host generic.port in
  let%lwt ctx = Conduit_lwt_unix.init () in
  let ctx = Cohttp_lwt_unix_net.init ~ctx () in
  let mode = `TCP (`Socket sock) in
  let conf = Server.make ~callback () in
  let (stop, close) = wait () in
  let thread = Server.create ~stop ~ctx ~mode conf in
  return {port = generic.port; sock; close; ctx; thread;}

let stop server =
  wakeup server.close ();
  let%lwt () = waiter_of_wakener server.close in
  Int.Table.add_exn open_sockets ~key:server.port ~data:server.sock;
  return_unit
