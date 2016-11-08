open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

type remote_t = {
  base_urls: Uri.t array;
  base_headers: Header.t;
  input_format: Io_format.t;
  output_format: Io_format.t;
  chan_separator: string;
} [@@deriving sexp]

let create base_urls base_headers ~input ~output ~chan_separator =
  let base_urls = Array.map ~f:Uri.of_string base_urls in
  let base_headers = Config_t.(
      Header.add_list
        (Header.init ())
        (List.map ~f:(fun pair -> (pair.key, pair.value)) base_headers)
    )
  in
  let input_format = Io_format.create input in
  let output_format = Io_format.create output in
  let instance = { base_urls; base_headers; input_format; output_format; chan_separator; } in
  return instance

let read_batch_size = 0

let get_base instance =
  let arr = instance.base_urls in
  Array.get arr (Random.int (Array.length arr))

module M = struct

  type t = remote_t [@@deriving sexp]

  let close instance = return_unit

  let push instance ~msgs ~ids =
    let open Json_obj_j in
    (* Body *)
    let payload = match instance.input_format with
      | Io_format.Plaintext ->
        String.concat_array ~sep:instance.chan_separator (Array.map ~f:B64.encode msgs)
      | Io_format.Json ->
        string_of_message { atomic = false; messages = msgs; ids = Some ids; }
    in
    print_endline payload;
    let body = Cohttp_lwt_body.of_string payload in

    (* Headers *)
    let headers = match instance.input_format with
      | Io_format.Plaintext ->
        Header.add_list instance.base_headers [
          Header_names.mode, "multiple";
          Header_names.id, (String.concat_array ~sep:Id.default_separator ids);
        ]
      | Io_format.Json ->
        Header.add instance.base_headers Header_names.mode "multiple"
    in

    (* Call *)
    let uri = get_base instance in
    let%lwt (response, body) = Client.call ~headers ~body ~chunked:false `POST uri in
    let%lwt body_str = Cohttp_lwt_body.to_string body in
    print_endline (Util.string_of_sexp ~pretty:true (Response.sexp_of_t response));
    print_endline (body_str);
    let%lwt parsed = Util.parse_json_lwt write_of_string body_str in
    match parsed.errors with
    | [] -> return (Option.value ~default:0 parsed.saved)
    | errors -> fail_with (String.concat ~sep:", " errors)

  let pull_slice instance ~search =
    let open Json_obj_j in
    let open Persistence in
    let mode = match search with
      | { filters = [| ((`After_id _) as mode) |]; limit; _ }
      | { filters = [| ((`After_ts _) as mode) |]; limit; _ } -> mode
      | { limit; _ } -> `Many limit
    in
    let headers = Header.add instance.base_headers Header_names.mode (Mode.Read.to_string mode) in

    (* Call *)
    let uri = get_base instance in
    let%lwt (response, body) = Client.call ~headers ~chunked:false `GET uri in
    let%lwt body_str = Cohttp_lwt_body.to_string body in
    print_endline (Util.string_of_sexp ~pretty:true (Response.sexp_of_t response));
    print_endline (body_str);
    let response_headers = Response.headers response in
    let%lwt (errors, messages) = match instance.output_format with
      | Io_format.Plaintext ->
        begin match Header.get response_headers "content-type" with
          | Some "application/json" ->
            let%lwt parsed = Util.parse_json_lwt errors_of_string body_str in
            return (parsed.errors, [| |])
          | _ ->
            let msgs = Util.split ~sep:instance.chan_separator body_str in
            return ([], Array.of_list_map ~f:B64.decode msgs)
        end
      | Io_format.Json ->
        let%lwt parsed = Util.parse_json_lwt read_of_string body_str in
        return (parsed.errors, parsed.messages)
    in
    match errors with
    | [] ->
      let metadata = begin match ((Header.get response_headers Header_names.last_id), (Header.get response_headers Header_names.last_ts)) with
        | (Some last_id), (Some last_timens) -> Some { last_id; last_timens; }
        | _ -> None
      end
      in
      return { metadata; payloads = messages; }
    | errors -> fail_with (String.concat ~sep:", " errors)

  let pull_stream instance ~search = fail_with "Unimplemented: Remote HTTP pull_stream"

  let size instance =
    return (Int.to_int64 20)

end
