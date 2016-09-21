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

type standard_routing = {
  write: (
    chan_name:string ->
    id_header:string option ->
    mode:Mode.Write.t ->
    string Lwt_stream.t ->
    (int, string list) Result.t Lwt.t);
  read: (
    chan_name:string ->
    id_header:string option ->
    mode:Mode.Read.t ->
    (string array * string, string list) Result.t Lwt.t);
  count: (
    chan_name:string ->
    mode:Mode.Count.t ->
    (int64, string list) Result.t Lwt.t);
}

type http_routing =
  | Admin
  | Standard of standard_routing

let mode_header_name = "newque-mode"
let id_header_name = "newque-msg-id"
let length_header_name = "newque-response-length"
let json_response_header = Header.init_with "Content-Type" "application/json"

let default_filter _ req _ =
  let path = Request.uri req |> Uri.path in
  let url_fragments = path |> String.split ~on:'/' in
  (* print_endline (List.sexp_of_t String.sexp_of_t url_fragments |> Util.string_of_sexp); *)
  let result = match url_fragments with
    | ""::"v1"::chan_name::"count"::_ ->
      begin match Request.meth req with
        | `GET -> Ok (chan_name, `Count)
        | meth -> Error (405, [Printf.sprintf "Invalid HTTP method %s" (Code.string_of_method meth)])
      end
    | ""::"v1"::chan_name::_ ->
      let mode_value =
        Header.get (Request.headers req) mode_header_name
        |> Result.of_option ~error:"<no header>"
        |> (Fn.flip Result.bind) Mode.of_string
      in
      begin match ((Request.meth req), mode_value) with
        | `POST, Ok (`Single as m)
        | `POST, Ok (`Multiple as m)
        | `POST, Ok (`Atomic as m)
        | `GET, Ok (`One as m)
        | `GET, Ok ((`Many _) as m)
        | `GET, Ok ((`After_id _) as m)
        | `GET, Ok ((`After_ts _) as m) -> Ok (chan_name, m)
        | _, Error str ->
          Error (400, [Printf.sprintf "Invalid %s header value: %s" mode_header_name str])
        | meth, _ ->
          Error (405, [Printf.sprintf "Invalid HTTP method %s" (Code.string_of_method meth)])
      end
    | _ -> Error (400, [Printf.sprintf "Invalid path %s" path])
  in
  return result

let json_write_body code errors saved =
  `Assoc [
    ("code", `Int code);
    ("errors", `List (List.map errors ~f:(fun x -> `String x)));
    ("saved", `Int saved);
  ]

let json_count_body code errors count =
  let count = if List.is_empty errors then `Int count else `Null in
  `Assoc [
    ("code", `Int code);
    ("errors", `List (List.map errors ~f:(fun x -> `String x)));
    ("count", count);
  ]

let json_body code errors =
  `Assoc [
    ("code", `Int code);
    ("errors", `List (List.map errors ~f:(fun x -> `String x)));
  ]

let handler http routing ((ch, _) as conn) req body =
  (* ignore (async (fun () -> Logger.debug_lazy (lazy (Util.string_of_sexp (Request.sexp_of_t req))))); *)
  let%lwt http = http in
  match%lwt default_filter conn req body with
  | Error (code, errors) ->
    let headers = json_response_header in
    let status = Code.status_of_code code in
    let body = Yojson.Basic.to_string (json_body code errors) in
    Server.respond_string ~headers ~status ~body ()
  | Ok (chan_name, mode) ->
    begin match Mode.wrap mode with

      | `Write mode ->
        let stream = Cohttp_lwt_body.to_stream body in
        let id_header = Header.get (Request.headers req) id_header_name in
        let%lwt (code, errors, saved) = begin try%lwt
            begin match%lwt routing.write ~chan_name ~id_header ~mode stream with
              | Ok count -> return (201, [], count)
              | Error errors -> return (400, errors, 0)
            end
          with ex -> return (500, [Exn.to_string ex], 0)
        end in
        let headers = json_response_header in
        let status = Code.status_of_code code in
        let body = Yojson.Basic.to_string (json_write_body code errors saved) in
        Server.respond_string ~headers ~status ~body ()

      | `Read mode ->
        let id_header = Header.get (Request.headers req) id_header_name in
        let%lwt (code, errors, read, sep) = begin try%lwt
            begin match%lwt routing.read ~chan_name ~id_header ~mode with
              | Ok (([| |] as arr), sep) -> return (204, [], arr, sep)
              | Ok (arr, sep) -> return (200, [], arr, sep)
              | Error errors -> return (400, errors, [| |], "")
            end
          with ex -> return (500, [Exn.to_string ex], [| |], "")
        end in
        let headers = Header.add_list (Header.init ()) [
            ("Content-Type", "application/octet-stream");
            (length_header_name, Int.to_string (Array.length read));
          ] in
        let status = Code.status_of_code code in
        (*
          Imperative, performance-sensitive code.
          Creates a separator array of the same length.
          Then sets the last separator to the empty string.
          The code that pushes to the stream is now branchless.
        *)
        let (stream, push) = Lwt_stream.create () in
        let separators = Array.create ~len:(Array.length read) sep in
        if not (Array.is_empty separators) then Array.nset separators (-1) "";
        let body_length = Array.foldi read ~init:0 ~f:(fun i acc elem ->
            let s = separators.(i) in
            push (Some elem);
            push (Some s);
            acc + (String.length elem) + (String.length s)
          ) in
        push (None); (* Terminates the stream *)
        print_endline (Request.headers req |> Header.to_string);
        let encoding = match Request.encoding req with
          | Transfer.Chunked -> Transfer.Chunked
          | Transfer.Unknown | Transfer.Fixed _ -> Transfer.Fixed (Int64.of_int body_length)
        in
        let response = Response.make ~status ~flush:true ~encoding ~headers () in
        let body = Cohttp_lwt_body.of_stream stream in
        return (response, body)

      | `Count as mode ->
        let%lwt (code, errors, count) = begin try%lwt
            begin match%lwt routing.count ~chan_name ~mode with
              | Ok count -> return (200, [], (Int64.to_int_exn count))
              | Error errors -> return (400, errors, 0)
            end
          with ex -> return (500, [Exn.to_string ex], 0)
        end in
        let headers = json_response_header in
        let status = Code.status_of_code code in
        let body = Yojson.Basic.to_string (json_count_body code errors count) in
        Server.respond_string ~headers ~status ~body ()
    end

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
    | Standard routing -> Server.make ~callback:(handler instance_t routing) ()
    | Admin -> Server.make ~callback:(Admin.handler) ()
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
