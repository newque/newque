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

  val pull : t -> search:search -> fetch_last:bool ->
    (* Returns the last rowid as first option *)
    (* Returns the last id and timens as second option if fetch_last is true *)
    (string array * int64 option * (string * int64) option) Lwt.t

  val delete : t -> unit Lwt.t

  val size : t -> int64 Lwt.t

  val health : t -> string list Lwt.t
end

module type Argument = sig
  module IO : Template
  val create : unit -> IO.t Lwt.t
  val stream_slice_size : int64
  val raw : bool
  val batching : Write_settings.batching option
end

module type S = sig
  type t [@@deriving sexp]

  val ready : unit -> unit Lwt.t

  val push : Message.t -> Id.t array -> int Lwt.t

  val pull_slice : int64 -> mode:Mode.Read.t -> only_once:bool -> slice Lwt.t

  val pull_stream : int64 -> mode:Mode.Read.t -> only_once:bool -> string Lwt_stream.t Lwt.t

  val size : unit -> int64 Lwt.t

  val delete : unit -> unit Lwt.t

  val health : unit -> string list Lwt.t
end

module Make (Argument: Argument) : S = struct
  type t = Argument.IO.t

  let sexp_of_t = Argument.IO.sexp_of_t
  let t_of_sexp = Argument.IO.t_of_sexp

  let instance = Argument.create ()

  let ready () =
    let%lwt _ = instance in
    return_unit

  (******************
     PUSH
   ********************)
  let fast_serialize =
    match Argument.raw with
    | true -> Message.serialize_raw
    | false -> Message.serialize_full

  let fast_push =
    let open Write_settings in
    match Argument.batching with
    | None ->
      fun msgs ids ->
        let%lwt instance = instance in
        Argument.IO.push instance ~msgs ~ids
    | Some { max_time; max_size = 1; _ } ->
      (* Special case optimization *)
      fun msgs ids ->
        let%lwt instance = instance in
        let threads = Util.array_to_list_rev_mapi msgs ~mapper:(fun i msg ->
            let%lwt _ = Argument.IO.push instance ~msgs:[| msg |] ~ids:[| Array.get ids i |] in
            return_unit
          )
        in
        let%lwt () = join threads in
        return (Array.length msgs)
    | Some { max_time; max_size; _ } ->
      let batcher = Batcher.create ~max_time ~max_size ~handler:(fun msgs ids ->
          let%lwt instance = instance in
          Argument.IO.push instance ~msgs ~ids
        )
      in
      fun msgs ids ->
        let threads = Util.array_to_list_rev_mapi msgs ~mapper:(fun i msg ->
            Batcher.submit batcher msg (Array.get ids i)
          )
        in
        let%lwt () = join threads in
        return (Array.length msgs)

  let push msgs ids =
    let msgs = fast_serialize msgs in
    fast_push msgs ids

  (******************
     PULL
   ********************)
  let fast_parse_exn =
    match Argument.raw with
    | true -> Fn.id
    | false ->
      fun raw_payloads -> Array.concat_map raw_payloads ~f:Message.parse_full_exn

  let pull_slice max_read ~mode ~only_once =
    let%lwt instance = instance in
    let search = create_search max_read ~mode ~only_once in
    let%lwt (raw_payloads, last_rowid, last_row_data) = Argument.IO.pull instance ~search ~fetch_last:true in
    wrap (fun () ->
      let payloads = fast_parse_exn raw_payloads in
      match last_row_data with
      | None ->
        { metadata = None; payloads }
      | Some (last_id, last_timens) ->
        let meta = { last_id; last_timens = (Int64.to_string last_timens); } in
        { metadata = (Some meta); payloads }
    )

  let pull_stream max_read ~mode ~only_once =
    let%lwt instance = instance in
    wrap4 (fun instance max_read mode only_once ->
      let search = create_search max_read ~mode ~only_once in
      (* Ugly imperative code for performance here *)
      let left = ref search.limit in
      let next_search = ref {search with limit = Int64.min !left Argument.stream_slice_size} in
      let raw_stream = Lwt_stream.from (fun () ->
          if !next_search.limit <= Int64.zero then return_none else
          let%lwt (payloads, last_rowid, last_row_data) = Argument.IO.pull instance ~search:!next_search ~fetch_last:false in
          let filter = match (last_rowid, last_row_data) with
            | None, None -> None
            | (Some rowid), _ -> Some [|`After_rowid rowid|]
            | _, Some (last_id, _) -> Some [|`After_id last_id|]
          in
          match filter with
          | None -> return_none
          | Some filter ->
            if Array.is_empty payloads then return_none else
            let payloads_count = Int.to_int64 (Array.length payloads) in
            left := Int64.(-) !left payloads_count;
            next_search := {
              !next_search with
              limit = Int64.min !left Argument.stream_slice_size;
              filters = Array.append filter search.filters;
            };
            return_some payloads
        )
      in
      let batch_size = Option.value (Int64.to_int Argument.stream_slice_size) ~default:Int.max_value in
      Util.stream_map_array_s raw_stream ~batch_size ~mapper:fast_parse_exn
    ) instance max_read mode only_once

  (******************
     SIZE
   ********************)
  let size () =
    let%lwt instance = instance in
    Argument.IO.size instance

  (******************
     DELETE
   ********************)
  let delete () =
    let%lwt instance = instance in
    Argument.IO.delete instance

  (******************
     HEALTH
   ********************)
  let health () =
    let%lwt instance = instance in
    Argument.IO.health instance

end
