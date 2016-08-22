open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

module Logger = Log.Make (struct let path = Log.outlog let section = "Http" end)

type t = {
  generic: Config_t.config_listener;
  specific: Config_t.config_http_settings;
  sock: Lwt_unix.file_descr;
  mutable filter: (Server.conn -> Request.t -> Cohttp_lwt_body.t -> (string * Mode.t, string) Result.t Lwt.t);
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

let mode_header = "newque-mode"

let default_filter _ req _ =
  let path = Request.uri req |> Uri.path in
  let url_fragments = path |> String.split ~on:'/' in
  let result = match url_fragments with
    | ""::chan_name::_ ->
      let mode_value =
        Request.headers req
        |> Fn.flip (Header.get) mode_header
        |> Option.map ~f:String.lowercase
      in
      begin match mode_value with
        | Some "multiple" -> Ok (chan_name, `Multiple)
        | Some "atomic" -> Ok (chan_name, `Atomic)
        | None | Some "single" -> Ok (chan_name, `Single)
        | Some str -> Error (Printf.sprintf "Invalid %s header value: %s" mode_header str)
      end
    | _ -> Error (Printf.sprintf "Invalid path %s" path)
  in
  return result

let json_post_body code errors saved =
  `Assoc [
    ("code", `Int code);
    ("errors", `List (List.map errors ~f:(fun x -> `String x)));
    ("saved", `Int saved);
  ]

let json_get_body code errors =
  `Assoc [
    ("code", `Int code);
    ("errors", `List (List.map errors ~f:(fun x -> `String x)));
  ]

let handler http route ((ch, _) as conn) req body =
  let%lwt http = http in
  match%lwt http.filter conn req body with
  | Error str ->
    let body = str in
    let status = Code.status_of_code 400 in
    Server.respond_string ~status ~body ()
  | Ok (chan_name, mode) ->
    let%lwt (code, json) = match Request.meth req with

      | `POST ->
        (* Publishing *)
        let stream = Cohttp_lwt_body.to_stream body in
        let%lwt (code, errors, saved) = begin match%lwt route ~chan_name ~mode stream with
          | Ok 0 -> return (400, ["No message found in the request body"], 0)
          | Ok count -> return (201, [], count)
          | Error err -> return (500, [err], 0)
        end in
        return (code, json_post_body code errors saved)

      | `GET ->
        (* Consuming *)
        return (200, json_get_body 200 [])

      | meth ->
        let err = Printf.sprintf "Invalid HTTP method %s" (Code.string_of_method meth) in
        return (405, json_get_body 405 [err])
    in
    let status = Code.status_of_code code in
    let body = Yojson.Basic.to_string json in
    Server.respond_string ~status ~body ()

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

let start generic specific route =
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
  let conf = Server.make ~callback:(handler instance_t route) () in
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
