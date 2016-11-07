open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

type remote_t = {
  base_urls: Uri.t array;
  base_headers: Header.t;
  input_format: Io_format.t;
  output_format: Io_format.t;
} [@@deriving sexp]

let create base_urls base_headers ~input ~output =
  let base_urls = Array.map ~f:Uri.of_string base_urls in
  let base_headers = Config_t.(
      Header.add_list
        (Header.init ())
        (List.map ~f:(fun pair -> (pair.key, pair.value)) base_headers)
    )
  in
  let input_format = Io_format.create input in
  let output_format = Io_format.create output in
  let instance = { base_urls; base_headers; input_format; output_format; } in
  return instance

let read_batch_size = 0

let get_base instance =
  let arr = instance.base_urls in
  Array.get arr (Random.int (Array.length arr))

module M = struct

  type t = remote_t [@@deriving sexp]

  let close instance = return_unit

  let push instance ~msgs ~ids =
    let open Config_j in
    let payload = string_of_input_message {
        atomic = false;
        messages = msgs;
        ids = Some ids;
      }
    in
    let uri = get_base instance in
    let body = Cohttp_lwt_body.of_string payload in
    let headers = Header.add_list instance.base_headers [
        Header_names.mode, "multiple";
      ]
    in
    let%lwt (response, body) = Client.call ~headers ~body ~chunked:false `POST uri in
    fail_with "derp"

  let pull_slice instance ~search = fail_with "Unimplemented: Remote HTTP pull_slice"

  let pull_stream instance ~search = fail_with "Unimplemented: Remote HTTP pull_stream"

  let size instance =
    return (Int.to_int64 20)

end
