open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

module Logger = Log.Make (struct let path = Log.outlog let section = "Httpproxy" end)

type httpproxy_t = {
  chan_name: string;
  base_urls: Uri.t array;
  base_headers: Header.t;
  timeout: float; (* seconds *)
  input_format: Http_format.t;
  output_format: Http_format.t;
  chan_separator: string;
} [@@deriving sexp]

let create ~chan_name base_urls base_headers timeout_ms ~input ~output ~chan_separator =
  let base_urls = Array.map ~f:Uri.of_string base_urls in
  let base_headers = Config_t.(
      Header.add_list
        (Header.init ())
        (List.map ~f:(fun pair -> (pair.key, pair.value)) base_headers)
    )
  in
  let instance = {
    chan_name;
    base_urls;
    base_headers;
    timeout = Float.(/) timeout_ms 1000.;
    input_format = Http_format.create input;
    output_format = Http_format.create output;
    chan_separator;
  }
  in
  return instance

let get_base instance =
  let arr = instance.base_urls in
  Array.get arr (Random.int (Array.length arr))

module M = struct

  type t = httpproxy_t [@@deriving sexp]

  let close instance = return_unit

  let push instance ~msgs ~ids =
    let open Json_obj_j in
    (* Body *)
    let payload = match instance.input_format with
      | Http_format.Plaintext ->
        String.concat_array ~sep:instance.chan_separator (Array.map ~f:B64.encode msgs)
      | Http_format.Json ->
        string_of_input { atomic = false; messages = msgs; ids = Some ids; }
    in
    let body = Cohttp_lwt_body.of_string payload in

    (* Headers *)
    let headers = match instance.input_format with
      | Http_format.Plaintext ->
        let mode_string = if Int.(=) (Array.length ids) 1 then "single" else "multiple" in
        Header.add_list instance.base_headers [
          Header_names.mode, mode_string;
          Header_names.id, (String.concat_array ~sep:Id.default_separator ids);
        ]
      | Http_format.Json ->
        Header.add instance.base_headers Header_names.mode "multiple"
    in

    (* Call *)
    let uri = get_base instance in
    let%lwt (response, body) = Http_tools.call ~headers ~body ~chunked:false ~timeout:instance.timeout `POST uri in
    let%lwt body_str = Cohttp_lwt_body.to_string body in
    let parsed = write_of_string body_str in
    match parsed.errors with
    | [] -> return (Option.value ~default:0 parsed.saved)
    | errors -> fail_with (String.concat ~sep:", " errors)

  let pull instance ~search ~fetch_last =
    let open Json_obj_j in
    let (mode, limit) = Search.mode_and_limit search in
    let headers = Header.add_list instance.base_headers [
        Header_names.mode, (Mode.Read.to_string mode);
        Header_names.limit, (Int64.to_string limit);
      ] in

    (* Call *)
    let uri = get_base instance in
    let%lwt (response, body) = Http_tools.call ~headers ~chunked:false ~timeout:instance.timeout `GET uri in
    let%lwt body_str = Cohttp_lwt_body.to_string body in
    let response_headers = Response.headers response in
    let%lwt (errors, messages) = match ((Response.status response), (instance.output_format)) with
      | `No_content, _ -> return ([], [| |])
      | _, Http_format.Plaintext ->
        begin match Header.get response_headers "content-type" with
          | Some "application/json" ->
            let parsed = errors_of_string body_str in
            return (parsed.errors, [| |])
          | _ ->
            let msgs = Util.split ~sep:instance.chan_separator body_str in
            return ([], Array.of_list_map ~f:B64.decode msgs)
        end
      | _, Http_format.Json ->
        let parsed = read_of_string body_str in
        return (parsed.errors, parsed.messages)
    in
    match errors with
    | [] ->
      let last_ts = Util.header_name_to_int64_opt response_headers Header_names.last_ts in
      let last_row_data = begin match ((Header.get response_headers Header_names.last_id), last_ts)
        with
        | (Some last_id), (Some last_timens) -> Some (last_id, last_timens)
        | _ -> None
      end
      in
      return (messages, None, last_row_data)
    | errors -> fail_with (String.concat ~sep:", " errors)

  let size instance =
    let open Json_obj_j in
    let headers = instance.base_headers in
    let uri = Http_tools.append_to_path (get_base instance) "count" in
    let%lwt (response, body) = Http_tools.call ~headers ~chunked:false ~timeout:instance.timeout `GET uri in
    let%lwt body_str = Cohttp_lwt_body.to_string body in
    let parsed = count_of_string body_str in
    match parsed.errors with
    | [] -> return (Option.value ~default:Int64.zero parsed.count)
    | errors -> fail_with (String.concat ~sep:", " errors)

  let delete instance =
    let open Json_obj_j in
    let%lwt () = Logger.info (sprintf "Deleting data in [%s]" instance.chan_name) in
    let headers = instance.base_headers in
    let uri = Http_tools.append_to_path (get_base instance) "delete" in
    let%lwt (response, body) = Http_tools.call ~headers ~chunked:false ~timeout:instance.timeout `DELETE uri in
    let%lwt body_str = Cohttp_lwt_body.to_string body in
    let parsed = errors_of_string body_str in
    match parsed.errors with
    | [] -> return_unit
    | errors -> fail_with (String.concat ~sep:", " errors)

  let health instance =
    let open Json_obj_j in
    let headers = instance.base_headers in
    let uri = Http_tools.append_to_path (get_base instance) "health" in
    try%lwt
      let%lwt (response, body) = Http_tools.call ~headers ~chunked:false ~timeout:instance.timeout `GET uri in
      let%lwt body_str = Cohttp_lwt_body.to_string body in
      let parsed = errors_of_string body_str in
      return parsed.errors
    with ex -> return (Exception.human_list ex)

end
