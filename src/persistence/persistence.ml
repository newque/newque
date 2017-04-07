open Core.Std
open Lwt

type slice_metadata = {
  last_id: string;
  last_timens: int64;
}
type slice = {
  metadata: slice_metadata option;
  payloads: string Collection.t;
}

module type Template = sig
  type t

  val close : t -> unit Lwt.t

  val push : t -> msgs:string Collection.t -> ids:string Collection.t -> int Lwt.t

  val pull : t -> search:Search.t -> fetch_last:bool ->
    (* Returns the last rowid as first option *)
    (* Returns the last id and timens as second option if fetch_last is true *)
    (string Collection.t * int64 option * (string * int64) option) Lwt.t

  val delete : t -> unit Lwt.t

  val size : t -> int64 Lwt.t

  val health : t -> string list Lwt.t
end

module type Argument = sig
  module IO : Template
  val create : unit -> IO.t Lwt.t
  val stream_slice_size : int64
  val raw : bool
  val scripting : Write_settings.scripting option
  val batching : Write_settings.batching option
end

module type S = sig
  type t

  val ready : unit -> unit Lwt.t

  val push : Message.t -> Id.t Collection.t -> int Lwt.t

  val pull_slice : int64 -> mode:Mode.Read.t -> only_once:bool -> slice Lwt.t

  val pull_stream : int64 -> mode:Mode.Read.t -> only_once:bool -> string Lwt_stream.t Lwt.t

  val size : unit -> int64 Lwt.t

  val delete : unit -> unit Lwt.t

  val health : unit -> string list Lwt.t
end

module Make (Argument: Argument) : S = struct
  type t = Argument.IO.t

  let instance = Argument.create ()

  let lua_opt_t = Option.map Argument.scripting ~f:(fun scripting ->
      Lua_scripting.create ~mappers:(scripting.Write_settings.mappers)
    )

  (******************
     PUSH
   ********************)
  let fast_serialize =
    match Argument.raw with
    | true -> Message.serialize_raw
    | false -> Message.serialize_full

  let fast_push_batching =
    let open Write_settings in
    match Argument.batching with
    | None ->
      fun msgs ids ->
        (* Runtime *)
        let%lwt instance = instance in
        Argument.IO.push instance ~msgs ~ids

    | Some { max_time; max_size = 1; _ } ->
      (* Special case optimization *)
      fun msgs ids ->
        (* Runtime *)
        let%lwt instance = instance in
        let threads =
          Collection.to_list_mapi_two msgs ids ~f:(fun i msg id ->
            let msgs = Collection.singleton msg in
            let ids = Collection.singleton id in
            let%lwt _ = Argument.IO.push instance ~msgs ~ids in
            return_unit
          )
          |> snd
        in
        let%lwt () = join threads in
        return (Collection.length msgs)

    | Some { max_time; max_size; _ } ->
      let batcher = Batcher.create ~max_time ~max_size ~handler:(fun msgs ids ->
          let%lwt instance = instance in
          Argument.IO.push instance ~msgs ~ids
        )
      in
      fun msgs ids ->
        (* Runtime *)
        let%lwt () = Batcher.submit batcher msgs ids in
        return (Collection.length msgs)

  let fast_push_scripting =
    let open Write_settings in
    match (Argument.scripting, lua_opt_t) with
    | None, None -> fast_push_batching
    | (Some { mappers }), (Some lua_t) ->
      fun msgs ids ->
        (* Runtime *)
        let%lwt lua = lua_t in
        let%lwt (mapped_msgs, mapped_ids) = Lua_scripting.run_mappers lua mappers ~msgs ~ids in
        fast_push_batching mapped_msgs mapped_ids
    | _ -> fast_push_batching (* Impossible case *)

  let push msgs ids =
    let msgs = fast_serialize msgs in
    fast_push_scripting msgs ids

  (******************
     PULL
   ********************)
  let fast_parse_exn =
    match Argument.raw with
    | true -> Fn.id
    | false ->
      fun raw_payloads ->
        Collection.to_list_concat_map raw_payloads ~f:Message.parse_full_exn
        |> fst

  let pull_slice max_read ~mode ~only_once =
    let%lwt instance = instance in
    let search = Search.create max_read ~mode ~only_once in
    let%lwt (raw_payloads, last_rowid, last_row_data) = Argument.IO.pull instance ~search ~fetch_last:true in
    wrap (fun () ->
      let payloads = fast_parse_exn raw_payloads in
      match last_row_data with
      | None ->
        { metadata = None; payloads }
      | Some (last_id, last_timens) ->
        let meta = { last_id; last_timens; } in
        { metadata = (Some meta); payloads }
    )

  let pull_stream max_read ~mode ~only_once =
    let open Search in
    let%lwt instance = instance in
    wrap4 (fun instance max_read mode only_once ->
      let search = Search.create max_read ~mode ~only_once in
      (* Ugly imperative code for performance here *)
      let left = ref search.limit in
      let next_search = ref {search with limit = Int64.min !left Argument.stream_slice_size} in
      let raw_stream = Lwt_stream.from (fun () ->
          if !next_search.limit <= Int64.zero
          then return_none else
          let%lwt (payloads, last_rowid, last_row_data) = Argument.IO.pull instance ~search:!next_search ~fetch_last:false in
          let filter = match (last_rowid, last_row_data) with
            | None, None -> None
            | (Some rowid), _ -> Some [|`After_rowid rowid|]
            | _, Some (last_id, _) -> Some [|`After_id last_id|]
          in
          if Collection.is_empty payloads
          then return_none else
          let payloads_count = Int.to_int64 (Collection.length payloads) in
          left := Int64.(-) !left payloads_count;
          next_search := begin match filter with
            | None ->
              (* Without a filter we can't continue streaming *)
              {
                !next_search with
                limit = Int64.zero;
              }
            | Some filter ->
              {
                !next_search with
                limit = Int64.min !left Argument.stream_slice_size;
                filters = Array.append filter search.filters;
              }
          end;
          return_some payloads
        )
      in
      let batch_size = Option.value (Int64.to_int Argument.stream_slice_size) ~default:Int.max_value in
      Util.coll_stream_flatten_map_s raw_stream ~batch_size ~mapper:fast_parse_exn
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

  (******************
     SETUP
   ********************)
  let ready () =
    let%lwt _ = instance in
    let%lwt () = match lua_opt_t with
      | None -> return_unit
      | Some lua_t ->
        let%lwt _ = lua_t in
        return_unit
    in
    return_unit

end
