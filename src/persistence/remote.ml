open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

type remote_t = {
  base_urls: Uri.t array;
  input_format: Io_format.t;
  output_format: Io_format.t;
} [@@deriving sexp]

let create base ~input ~output =
  let base_urls = Array.map ~f:Uri.of_string base in
  let input_format = Io_format.create input in
  let output_format = Io_format.create output in
  let instance = { base_urls; input_format; output_format; } in
  return instance

let read_batch_size = 0

let get_base instance =
  let arr = instance.base_urls in
  Array.get arr (Random.int (Array.length arr))

module M = struct

  type t = remote_t [@@deriving sexp]

  let close instance = return_unit

  let push instance ~msgs ~ids = return 1
  (* let open Config_t in
     let payload = {
     messages = 
     } *)

  let pull_slice instance ~search = fail_with "Unimplemented: Remote HTTP pull_slice"

  let pull_stream instance ~search = fail_with "Unimplemented: Remote HTTP pull_stream"

  let size instance =
    return (Int.to_int64 20)

end
