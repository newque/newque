open Core.Std
open Lwt

type search = {
  limit: int64;
  filters: [ `After_id of string | `After_ts of int64 | `After_rowid of int64 | `Tag of string ] array;
  only_once: bool;
} [@@deriving sexp]

let create_search max_read ~mode ~only_once =
  match mode with
  | `One -> { limit = Int64.one; filters = [| |]; only_once; }
  | `Many x -> { limit = (Int64.min max_read x); filters = [| |]; only_once; }
  | `After_id id -> { limit = max_read; filters = [|`After_id id|]; only_once; }
  | `After_ts ts -> { limit = max_read; filters = [|`After_ts ts|]; only_once; }

type slice_metadata = {
  last_id: string;
  last_timens: string;
}
type slice = {
  metadata: slice_metadata option;
  payloads: string array;
}

module type Template = sig
  type t [@@deriving sexp]

  val close : t -> unit Lwt.t

  val push : t -> msgs:string array -> ids:string array -> int Lwt.t

  val pull_slice : t -> search:search -> slice Lwt.t

  val pull_stream : t -> search:search -> string array Lwt_stream.t Lwt.t

  val size : t -> int64 Lwt.t
end

module type Argument = sig
  module IO : Template
  val create : unit -> IO.t Lwt.t
  val read_batch_size: int
end

module type S = sig
  type t [@@deriving sexp]

  val push : Message.t array -> Id.t array -> int Lwt.t

  val pull_slice : int64 -> mode:Mode.Read.t -> only_once:bool -> slice Lwt.t

  val pull_stream : int64 -> mode:Mode.Read.t -> only_once:bool -> string Lwt_stream.t Lwt.t

  val size : unit -> int64 Lwt.t
end

module Make (Argument: Argument) : S = struct
  type t = Argument.IO.t

  let sexp_of_t = Argument.IO.sexp_of_t
  let t_of_sexp = Argument.IO.t_of_sexp

  let instance = Argument.create ()

  let push msgs ids =
    let%lwt instance = instance in
    let ids = Array.map ~f:Id.to_string ids in
    let msgs = Array.map ~f:Message.serialize msgs in
    Argument.IO.push instance ~msgs ~ids

  let pull_slice max_read ~mode ~only_once =
    let%lwt instance = instance in
    let search = create_search max_read ~mode ~only_once in
    let%lwt slice = Argument.IO.pull_slice instance ~search in
    wrap (fun () ->
      {
        slice with
        payloads =
          Array.concat_map slice.payloads ~f:(fun x ->
            Message.contents (Message.parse_exn x)
          )
      }
    )

  let pull_stream max_read ~mode ~only_once =
    let%lwt instance = instance in
    let search = create_search max_read ~mode ~only_once in
    let%lwt data = Argument.IO.pull_stream instance ~search in
    let mapper = fun raw ->
      Array.concat_map raw ~f:(fun x -> Message.contents (Message.parse_exn x))
    in
    let stream = Util.stream_map_array_s data ~batch_size:Argument.read_batch_size ~mapper in
    return stream

  let size () =
    let%lwt instance = instance in
    Argument.IO.size instance

end
