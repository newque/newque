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
  push: (
    chan_name:string ->
    id_header:string option ->
    mode:Mode.Write.t ->
    string Lwt_stream.t ->
    (int option, string list) Result.t Lwt.t);
  read_slice: (
    chan_name:string ->
    id_header:string option ->
    mode:Mode.Read.t ->
    (Persistence.slice * Channel.t, string list) Result.t Lwt.t);
  read_stream: (
    chan_name:string ->
    id_header:string option ->
    mode:Mode.Read.t ->
    (string Lwt_stream.t * Channel.t, string list) Result.t Lwt.t);
  count: (
    chan_name:string ->
    mode:Mode.Count.t ->
    (int64, string list) Result.t Lwt.t);
}

type http_routing =
  | Admin
  | Standard of standard_routing

let default_filter _ req _ =
  let path = Request.uri req |> Uri.path in
  let url_fragments = path |> String.split ~on:'/' in
  let result = match url_fragments with
    | ""::"v1"::chan_name::"count"::_ ->
      begin match Request.meth req with
        | `GET -> Ok (chan_name, `Count)
        | meth -> Error (405, [Printf.sprintf "Invalid HTTP method %s" (Code.string_of_method meth)])
      end
    | ""::"v1"::chan_name::_ ->
      let mode_value =
        Header.get (Request.headers req) Header_names.mode
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
        | `POST, Error "<no header>" -> Ok (chan_name, `Single)
        | (`POST as meth), Ok m
        | (`GET as meth), Ok m ->
          Error (400, [Printf.sprintf "Invalid {Method, Mode} pair: {%s, %s}" (Code.string_of_method meth) (Mode.to_string (m :> Mode.Any.t))])
        | _, Error str ->
          Error (400, [Printf.sprintf "Invalid %s header value: %s" Header_names.mode str])
        | meth, _ ->
          Error (405, [Printf.sprintf "Invalid HTTP method %s" (Code.string_of_method meth)])
      end
    | _ -> Error (400, [Printf.sprintf "Invalid path %s" path])
  in
  return result

let json_response_header = Header.init_with "content-type" "application/json"

let handle_errors code errors =
  let headers = json_response_header in
  let status = Code.status_of_code code in
  let body = Json_obj_j.(string_of_errors { code; errors; }) in
  Server.respond_string ~headers ~status ~body ()

let handler http routing ((ch, _) as conn) req body =
  (* async (fun () -> Logger.debug_lazy (lazy (Util.string_of_sexp (Request.sexp_of_t req)))); *)
  let%lwt http = http in
  match%lwt default_filter conn req body with
  | Error (code, errors) -> handle_errors code errors
  | Ok (chan_name, mode) ->
    begin try%lwt
        begin match Mode.wrap mode with

          | `Write mode ->
            let stream = Cohttp_lwt_body.to_stream body in
            let id_header = Header.get (Request.headers req) Header_names.id in
            let%lwt (code, errors, saved) =
              begin match%lwt routing.push ~chan_name ~id_header ~mode stream with
                | Ok ((Some _) as count) -> return (201, [], count)
                | Ok None -> return (202, [], None)
                | Error errors -> return (400, errors, (Some 0))
              end in
            let headers = json_response_header in
            let status = Code.status_of_code code in
            let body = Json_obj_j.(string_of_write { code; errors; saved; }) in
            Server.respond_string ~headers ~status ~body ()

          | `Read mode ->
            let id_header = Header.get (Request.headers req) Header_names.id in
            begin match Request.encoding req with
              | Transfer.Chunked ->
                begin match%lwt routing.read_stream ~chan_name ~id_header ~mode with
                  | Error errors -> handle_errors 400 errors
                  | Ok (stream, channel) ->
                    let%lwt status, headers = match%lwt Lwt_stream.is_empty stream with
                      | false -> return (
                          (Code.status_of_code 200),
                          (Header.add_list (Header.init ()) [("content-type", "application/octet-stream")])
                        )
                      | true -> return (
                          (Code.status_of_code 204),
                          (Header.add_list (Header.init ()) [
                              ("content-type", "application/octet-stream");
                              (Header_names.length, "0");
                            ])
                        )
                    in
                    let sep = channel.Channel.separator in
                    let body_stream = Lwt_stream.map_list_s (fun raw ->
                        begin match%lwt Lwt_stream.is_empty stream with
                          | true -> return [raw]
                          | false -> return [raw; sep]
                        end
                      ) stream in
                    let encoding = Transfer.Chunked in
                    let response = Response.make ~status ~flush:true ~encoding ~headers () in
                    let body = Cohttp_lwt_body.of_stream body_stream in
                    return (response, body)
                end
              | Transfer.Unknown | Transfer.Fixed _ ->
                begin match%lwt routing.read_slice ~chan_name ~id_header ~mode with
                  | Error errors -> handle_errors 400 errors
                  | Ok (slice, channel) ->
                    let open Persistence in
                    let payloads = slice.payloads in
                    let code = if Array.is_empty payloads then 204 else 200 in
                    let status = Code.status_of_code code in
                    let headers = match slice.metadata with
                      | None ->
                        Header.add_list (Header.init ()) [
                          ("content-type", "application/octet-stream");
                          (Header_names.length, Int.to_string (Array.length payloads));
                        ]
                      | Some metadata ->
                        Header.add_list (Header.init ()) [
                          ("content-type", "application/octet-stream");
                          (Header_names.length, Int.to_string (Array.length payloads));
                          (Header_names.last_id, metadata.last_id);
                          (Header_names.last_ts, metadata.last_timens);
                        ]
                    in
                    let open Read_settings in
                    let body = match channel.Channel.read with
                      | None ->
                        let err = Printf.sprintf "Impossible case: Missing readSettings for channel %s" chan_name in
                        async (fun () -> Logger.error err);
                        Json_obj_j.(string_of_read { code = 500; errors = [err]; messages = [| |]; })
                      | Some { format = Io_format.Plaintext } ->
                        String.concat_array ~sep:channel.Channel.separator payloads
                      | Some { format = Io_format.Json } ->
                        Json_obj_j.(string_of_read { code; errors = []; messages = payloads; })
                    in
                    let encoding = Transfer.Fixed (Int.to_int64 (String.length body)) in
                    let response = Response.make ~status ~flush:true ~encoding ~headers () in
                    return (response, (Cohttp_lwt_body.of_string body))
                end
            end

          | `Count as mode ->
            let%lwt (code, errors, count) =
              begin match%lwt routing.count ~chan_name ~mode with
                | Ok count -> return (200, [], Some (Int64.to_int_exn count))
                | Error errors -> return (400, errors, None)
              end in
            let headers = json_response_header in
            let status = Code.status_of_code code in
            let body = Json_obj_j.(string_of_count { code; errors; count; }) in
            Server.respond_string ~headers ~status ~body ()
        end
      with ex -> handle_errors 500 [Exn.to_string ex]
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
