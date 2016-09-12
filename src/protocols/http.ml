open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

module Logger = Log.Make (struct let path = Log.outlog let section = "Http" end)

type t = {
  generic: Config_t.config_listener;
  specific: Config_t.config_http_settings;
  sock: Lwt_unix.file_descr;
  close: unit Lwt.u;
  ctx: Cohttp_lwt_unix_net.ctx;
  thread: unit Lwt.t;
}
let sexp_of_t http =
  let open Config_t in
  Sexp.List [
    Sexp.List [
      Sexp.Atom http.generic.name;
      Sexp.Atom http.generic.host;
      Sexp.Atom (Int.to_string http.generic.port);
    ];
    Sexp.List [
      Sexp.Atom (Int.to_string http.specific.backlog);
    ];
  ]

type http_routing = [
  | `Admin
  | `Standard of (
      chan_name:string ->
      id_header:string option ->
      mode:Mode.Pub.t ->
      string Lwt_stream.t ->
      (int, string list) Result.t Lwt.t
    )
]

let mode_header_name = "newque-mode"
let id_header_name = "newque-msg-id"

let default_filter _ req _ =
  let path = Request.uri req |> Uri.path in
  let url_fragments = path |> String.split ~on:'/' in
  let result = match url_fragments with
    | ""::chan_name::_ ->
      let mode_value =
        Request.headers req
        |> Fn.flip (Header.get) mode_header_name
        |> Option.map ~f:String.lowercase
      in
      begin match ((Request.meth req), mode_value) with
        | `POST, (Some "multiple") -> Ok (chan_name, `Pub `Multiple)
        | `POST, (Some "atomic") -> Ok (chan_name, `Pub `Atomic)
        | `POST, (Some "single") | `POST, None ->
          Ok (chan_name, `Pub `Single)
        | `POST, (Some str) ->
          Error (400, [Printf.sprintf "Invalid %s header value: %s" mode_header_name str])
        | meth, _ ->
          Error (405, [Printf.sprintf "Invalid HTTP method %s" (Code.string_of_method meth)])
      end
    | _ -> Error (400, [Printf.sprintf "Invalid path %s" path])
  in
  return result

let json_pub_body code errors saved =
  `Assoc [
    ("code", `Int code);
    ("errors", `List (List.map errors ~f:(fun x -> `String x)));
    ("saved", `Int saved);
  ]

let json_body code errors =
  `Assoc [
    ("code", `Int code);
    ("errors", `List (List.map errors ~f:(fun x -> `String x)));
    ("saved", `Int 0);
  ]

let handler http publish ((ch, _) as conn) req body =
  (* ignore (async (fun () -> Logger.debug_lazy (lazy (Util.string_of_sexp (Request.sexp_of_t req))))); *)
  let%lwt http = http in
  let%lwt (code, json) = match%lwt default_filter conn req body with
    | Error (code, errors) -> return (code, json_body code errors)
    | Ok (chan_name, m) ->
      match m with
      | `Pub mode ->
        let stream = Cohttp_lwt_body.to_stream body in
        let id_header = Header.get (Request.headers req) id_header_name in
        let%lwt (code, errors, saved) = begin try%lwt
            begin match%lwt publish ~chan_name ~id_header ~mode stream with
              | Ok count -> return (201, [], count)
              | Error errors -> return (400, errors, 0)
            end
          with
          | ex -> return (400, [Exn.to_string ex], 0)
        end
        in
        return (code, json_pub_body code errors saved)
      | `Sub _ ->
        return (200, json_body 200 [])
  in
  let status = Code.status_of_code code in
  let body = Yojson.Basic.to_string json in
  let headers = Header.init_with "Content-Type" "application/json" in
  Server.respond_string ~headers ~status ~body ()

let open_sockets = Int.Table.create ~size:5 ()

let healthy_socket sock =
  try%lwt
    Lwt_unix.check_descriptor sock;
    return_true
  with
  | _ -> return_false

let make_socket ~backlog host port =
  let open Lwt_unix in
  let%lwt () = Logger.notice (Printf.sprintf "Creating a new TCP socket on %s:%d" host port) in
  let%lwt info = Lwt_unix.getaddrinfo host "0" [AI_PASSIVE; AI_SOCKTYPE SOCK_STREAM] in
  let%lwt (sockaddr, ip) = match List.hd info with
    | Some {ai_addr = (ADDR_UNIX _)} -> fail_with "Cant listen to TCP on a domain socket"
    | Some {ai_addr = (ADDR_INET (a,_))} -> return (ADDR_INET (a,port), Ipaddr_unix.of_inet_addr a)
    | None -> return (ADDR_INET (Unix.Inet_addr.bind_any,port), Ipaddr.(V4 V4.any))
  in
  let sock = Lwt_unix.socket (Unix.domain_of_sockaddr sockaddr)
      Unix.SOCK_STREAM 0 in
  Lwt_unix.setsockopt sock SO_REUSEADDR true;
  Lwt_unix.bind sock sockaddr;
  Lwt_unix.listen sock backlog;
  Lwt_unix.set_close_on_exec sock;
  return sock

let start generic specific http_routing_kind =
  let open Config_t in
  let thunk () = make_socket ~backlog:specific.backlog generic.host generic.port in
  let%lwt sock = match Int.Table.find_and_remove open_sockets generic.port with
    | Some s ->
      begin match%lwt healthy_socket s with
        | true -> return s
        | false -> thunk ()
      end
    | None -> thunk ()
  in
  let%lwt ctx = Conduit_lwt_unix.init () in
  let ctx = Cohttp_lwt_unix_net.init ~ctx () in
  let mode = `TCP (`Socket sock) in
  let (instance_t, instance_w) = wait () in
  let conf = match http_routing_kind with
    | `Standard publish -> Server.make ~callback:(handler instance_t publish) ()
    | `Admin -> Server.make ~callback:(Admin.handler) ()
  in
  let (stop, close) = wait () in
  let thread = Server.create ~stop ~ctx ~mode conf in
  let instance = {generic; specific; sock; close; ctx; thread;} in
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
