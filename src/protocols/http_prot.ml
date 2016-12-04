open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

module Logger = Log.Make (struct let path = Log.outlog let section = "Http" end)

type t = {
  generic: Config_t.config_listener;
  specific: Config_t.config_http_settings;
  sock: Lwt_unix.file_descr;
  stop_w: unit Lwt.u;
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

let missing_header = "<no header>"

let default_filter _ req _ =
  let path = Uri.path (Request.uri req) in
  let url_fragments = String.split ~on:'/' path in
  let result = match url_fragments with
    | ""::"v1"::"health"::_ ->
      begin match Request.meth req with
        | `GET -> Ok (None, `Health)
        | meth -> Error (405, [sprintf "Invalid HTTP method %s for health" (Code.string_of_method meth)])
      end
    | ""::"v1"::chan_name::"health"::_ ->
      begin match Request.meth req with
        | `GET -> Ok (Some chan_name, `Health)
        | meth -> Error (405, [sprintf "Invalid HTTP method %s for health" (Code.string_of_method meth)])
      end
    | ""::"v1"::chan_name::"count"::_ ->
      begin match Request.meth req with
        | `GET -> Ok (Some chan_name, `Count)
        | meth -> Error (405, [sprintf "Invalid HTTP method %s for count" (Code.string_of_method meth)])
      end
    | ""::"v1"::chan_name::_ ->
      let mode_opt = Header.get (Request.headers req) Header_names.mode in
      let mode_string = Option.value ~default:missing_header mode_opt in
      let mode_value = Result.bind (Result.of_option ~error:missing_header mode_opt) Mode.of_string in
      begin match ((Request.meth req), mode_value) with
        | `DELETE, _ ->
          Ok (Some chan_name, `Delete)
        | `POST, Ok (`Single as m)
        | `POST, Ok (`Multiple as m)
        | `POST, Ok (`Atomic as m)
        | `GET, Ok (`One as m)
        | `GET, Ok ((`Many _) as m)
        | `GET, Ok ((`After_id _) as m)
        | `GET, Ok ((`After_ts _) as m) ->
          Ok (Some chan_name, Mode.wrap m)
        | `POST, Error err when String.(=) err missing_header ->
          Ok (Some chan_name, Mode.wrap `Single)
        | meth, Ok m ->
          Error (400, [sprintf "Invalid {Method, Mode} pair: {%s, %s}" (Code.string_of_method meth) (Mode.to_string (m :> Mode.Any.t))])
        | meth, Error _ ->
          Error (400, [sprintf "Invalid {Method, Mode} pair: {%s, %s}" (Code.string_of_method meth) mode_string])
      end
    | _ -> Error (400, [sprintf "Invalid path %s (should begin with /v1/)" path])
  in
  return result

let json_response_header = Header.init_with "content-type" "application/json"

let handle_errors code errors =
  let headers = json_response_header in
  let status = Code.status_of_code code in
  let body = Json_obj_j.(string_of_errors { code; errors; }) in
  Server.respond_string ~headers ~status ~body ()

let handler http routing ((ch, _) as conn) req body =
  let open Routing in
  (* async (fun () -> Logger.warning_lazy (lazy (Util.string_of_sexp (Request.sexp_of_t req)))); *)
  let%lwt http = http in
  try%lwt
    begin match%lwt default_filter conn req body with
      | Error (code, errors) -> handle_errors code errors

      | Ok (Some chan_name, `Write mode) ->
        let stream = Cohttp_lwt_body.to_stream body in
        let id_header = Header.get (Request.headers req) Header_names.id in
        let%lwt (code, errors, saved) =
          begin match%lwt routing.write_http ~chan_name ~id_header ~mode stream with
            | Ok ((Some _) as count) -> return (201, [], count)
            | Ok None -> return (202, [], None)
            | Error errors -> return (400, errors, (Some 0))
          end
        in
        let headers = json_response_header in
        let status = Code.status_of_code code in
        let body = Json_obj_j.(string_of_write { code; errors; saved; }) in
        Server.respond_string ~headers ~status ~body ()

      | Ok (Some chan_name, `Read mode) ->
        begin match Request.encoding req with
          | Transfer.Chunked ->
            begin match%lwt routing.read_stream ~chan_name ~mode with
              | Error errors -> handle_errors 400 errors
              | Ok (stream, channel) ->
                let status = Code.status_of_code 200 in
                let%lwt headers = match%lwt Lwt_stream.is_empty stream with
                  | false -> return (Header.add_list (Header.init ()) [
                      ("content-type", "application/octet-stream")
                    ])
                  | true -> return (
                      Header.add_list (Header.init ()) [
                        ("content-type", "application/octet-stream");
                        (Header_names.length, "0");
                      ])
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
            let limit = Util.header_name_to_int64_opt (Request.headers req) Header_names.limit in
            begin match%lwt routing.read_slice ~chan_name ~mode ~limit with
              | Error errors -> handle_errors 400 errors
              | Ok (slice, channel) ->
                let open Persistence in
                let payloads = slice.payloads in
                let code = 200 in
                let status = Code.status_of_code code in
                let headers = match slice.metadata with
                  | None ->
                    Header.add_list (Header.init ()) [
                      (Header_names.length, Int.to_string (Array.length payloads));
                    ]
                  | Some metadata ->
                    Header.add_list (Header.init ()) [
                      (Header_names.length, Int.to_string (Array.length payloads));
                      (Header_names.last_id, metadata.last_id);
                      (Header_names.last_ts, metadata.last_timens);
                    ]
                in
                let open Read_settings in
                let (body, headers) = match channel.Channel.read with
                  | None ->
                    let err = sprintf "Impossible case: Missing readSettings for channel %s" chan_name in
                    async (fun () -> Logger.error err);
                    let headers = Header.add headers "content-type" "application/json" in
                    let body = Json_obj_j.(string_of_read { code = 500; errors = [err]; messages = [| |]; }) in
                    (body, headers)
                  | Some { http_format = Http_format.Plaintext } ->
                    let headers = Header.add headers "content-type" "application/octet-stream" in
                    let body = String.concat_array ~sep:channel.Channel.separator payloads in
                    (body, headers)
                  | Some { http_format = Http_format.Json } ->
                    let headers = Header.add headers "content-type" "application/json" in
                    let body = Json_obj_j.(string_of_read { code; errors = []; messages = payloads; }) in
                    (body, headers)
                in
                let encoding = Transfer.Fixed (Int.to_int64 (String.length body)) in
                let response = Response.make ~status ~flush:true ~encoding ~headers () in
                return (response, (Cohttp_lwt_body.of_string body))
            end
        end

      | Ok (Some chan_name, (`Count as mode)) ->
        let%lwt (code, errors, count) =
          begin match%lwt routing.count ~chan_name ~mode with
            | Ok count -> return (200, [], Some count)
            | Error errors -> return (400, errors, None)
          end
        in
        let headers = json_response_header in
        let status = Code.status_of_code code in
        let body = Json_obj_j.(string_of_count { code; errors; count; }) in
        Server.respond_string ~headers ~status ~body ()

      | Ok (Some chan_name, (`Delete as mode)) ->
        let%lwt (code, errors) =
          begin match%lwt routing.delete ~chan_name ~mode with
            | Ok () -> return (200, [])
            | Error errors -> return (400, errors)
          end
        in
        let headers = json_response_header in
        let status = Code.status_of_code code in
        let body = Json_obj_j.(string_of_errors { code; errors; }) in
        Server.respond_string ~headers ~status ~body ()

      | Ok ((Some _) as chan_name, (`Health as mode))
      | Ok (None as chan_name, (`Health as mode)) ->
        let%lwt (code, errors) =
          begin match%lwt routing.health ~chan_name ~mode with
            | [] as ll -> return (200, ll)
            | errors -> return (500, errors)
          end
        in
        let headers = json_response_header in
        let status = Code.status_of_code code in
        let body = Json_obj_j.(string_of_errors { code; errors; }) in
        Server.respond_string ~headers ~status ~body ()
      | Ok (None, _) -> fail_with "Invalid routing"
    end
  with
  | Exception.Multiple_exn errors -> handle_errors 500 errors
  | Failure str -> handle_errors 500 [str]
  | ex -> handle_errors 500 [Exn.to_string ex]

let open_sockets = Int.Table.create ~size:5 ()

let make_socket ~backlog host port =
  let open Lwt_unix in
  let%lwt () = Logger.notice (sprintf "Creating a new TCP socket on %s:%d" host port) in
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

let start generic specific routing =
  let open Config_t in
  let open Routing in
  let thunk () = make_socket ~backlog:specific.backlog generic.host generic.port in
  let%lwt sock = match Int.Table.find_and_remove open_sockets generic.port with
    | Some s ->
      begin match%lwt Fs.healthy_fd s with
        | true -> return s
        | false -> thunk ()
      end
    | None -> thunk ()
  in
  let%lwt ctx = Conduit_lwt_unix.init () in
  let ctx = Cohttp_lwt_unix_net.init ~ctx () in
  let mode = `TCP (`Socket sock) in
  let (instance_t, instance_w) = wait () in
  let conf = match routing with
    | Standard routing -> Server.make ~callback:(handler instance_t routing) ()
    | Admin {table} -> Server.make ~callback:(Admin.handler table) ()
  in
  let (stop_t, stop_w) = wait () in
  let thread = Server.create ~stop:stop_t ~ctx ~mode conf in
  let instance = {generic; specific; sock; stop_w; ctx; thread;} in
  wakeup instance_w instance;
  return instance

let stop http =
  let open Config_t in
  wakeup http.stop_w ();
  let%lwt () = waiter_of_wakener http.stop_w in
  Int.Table.add_exn open_sockets ~key:http.generic.port ~data:http.sock;
  return_unit

let close http =
  let open Config_t in
  let%lwt () = stop http in
  match Int.Table.find_and_remove open_sockets http.generic.port with
  | Some s -> Lwt_unix.close s
  | None -> return_unit
