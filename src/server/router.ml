open Core
open Lwt

module Logger = Log.Make (struct let section = "Router" end)

type t = {
  table: Channel.t String.Table.t String.Table.t; (* Channels (accessed by name) by listener.id *)
}

let create () =
  let table = String.Table.create () in
  (* Register the catch-all private listener *)
  let data = String.Table.create () in
  String.Table.add_exn table ~key:Listener.(private_listener.id) ~data;
  {table}

let register_listeners router listeners =
  let open Listener in
  List.filter_map listeners ~f:(fun listen ->
    let entry = String.Table.create () in
    match String.Table.add router.table ~key:listen.id ~data:entry with
    | `Ok -> None
    | `Duplicate -> Some (sprintf "Cannot register listener [%s] because it already exists" listen.id)
  )
  |> fun ll -> if List.length ll = 0 then Ok () else Error ll

(* Important: At this time, listeners must exist prior to adding channels *)
let register_channels router channels =
  let open Channel in
  List.concat_map channels ~f:(fun chan ->
    (* Every channel also registers with the private listener *)
    let chan_endpoints = Listener.(private_listener.id) :: chan.endpoint_names in
    List.filter_map chan_endpoints ~f:(fun listen_name ->
      match String.Table.find router.table listen_name with
      | Some chan_table ->
        begin match String.Table.add chan_table ~key:chan.name ~data:chan with
          | `Ok -> None
          | `Duplicate -> Some (
              sprintf
                "Registered channel [%s] with listener [%s] but another channel with the same name already existed"
                chan.name listen_name
            )
        end
      | None -> Some (sprintf "Cannot add channel [%s] to [%s]. Does that listener exist?" chan.name listen_name)
    ))
  |> function
  | [] -> Ok ()
  | errors -> Error errors

let find_chan router ~listen_name ~chan_name =
  match String.Table.find router.table listen_name with
  | None -> Error (sprintf "Unknown listener [%s]" listen_name)
  | Some chan_table ->
    begin match String.Table.find chan_table chan_name with
      | None -> Error (sprintf "No channel [%s] associated with listener [%s]" chan_name listen_name)
      | Some chan -> Ok chan
    end

let all_channels router =
  match String.Table.find router.table Listener.(private_listener.id) with
  | None -> fail_with "Cannot find internal private listener"
  | Some priv -> return (String.Table.to_alist priv)

(******************
   WRITE
 ******************)

(* Actually write to the channel *)
let write_shared router ~listen_name ~chan ~write ~msgs ~ids =
  let open Channel in
  let open Write_settings in
  begin match ((Message.length ~raw:chan.raw msgs), (Collection.length ids)) with
    | (0, _) -> return (Error [sprintf "Nothing to write"])
    | (msgs_l, ids_l) when Int.(<>) msgs_l ids_l -> return (Error [sprintf "Length mismatch between messages [%d] and IDs [%d]" msgs_l ids_l])
    | _ ->
      let save_t =
        let%lwt count = Channel.push chan msgs ids in
        async (fun () ->
          Logger.debug_lazy (lazy (
            sprintf "Wrote: (length: %d) to [%s] from [%s]" count chan.name listen_name
          ))
        );
        (* Forward to other channels if needed. *)
        let%lwt () = Lwt_list.iter_p (fun forward_chan_name ->
            begin match find_chan router ~listen_name:Listener.(private_listener.id) ~chan_name:forward_chan_name with
              | Error _ -> Logger.error (sprintf "Cannot forward from [%s] to [%s] because [%s] doesn't exist" chan.name forward_chan_name forward_chan_name)
              | Ok forward_chan ->
                let%lwt forward_count = Channel.push forward_chan msgs ids in
                if Int.(<>) forward_count count
                then async (fun () ->
                    Logger.notice_lazy (lazy (
                      sprintf "Mismatch while forwarding from [%s] (wrote %d) to [%s] (wrote %d). Possible ID collision(s)" chan.name count forward_chan_name forward_count
                    ))
                  );
                return_unit
            end
          ) write.forward
        in
        return (Ok (Some count))
      in
      begin match write.ack with
        | Saved -> save_t
        | Instant ->
          async (fun () -> save_t);
          return (Ok None)
      end
  end

(*
  The HTTP server doesn't know about the channel settings, so there's no point
  parsing the entire body for nothing if the channel isn't writeable (for example).
*)
let write_http router ~listen_name ~chan_name ~id_header ~mode stream =
  match find_chan router ~listen_name ~chan_name with
  | Error err -> return (Error [err])
  | Ok chan ->
    let open Channel in
    begin match chan.write with
      | None -> return (Error [sprintf "Channel [%s] doesn't support Writing to it" chan_name])
      | Some write ->
        let open Write_settings in

        (* For JSON: Read the whole body, then generate IDs if needed *)
        (* For Plaintext: Use the stream parser *)
        let%lwt parsed = begin match write.http_format with
          | Http_format.Json ->
            let%lwt str = Util.stream_to_string ~buffer_size:chan.buffer_size stream in
            let open Json_obj_j in
            begin match Util.parse_sync input_array_of_string str with
              | (Error _) as err ->
                let dummy = Message.of_string_coll ~atomic:false Collection.empty in
                return (dummy, err)
              | Ok { atomic; messages; ids } ->
                let msgs = Message.of_string_coll ~atomic (Collection.of_array messages) in
                let mode = if Bool.(=) atomic true then `Atomic else `Multiple in
                begin match ids with
                  | Some ids -> return (msgs, Ok (Collection.of_array ids))
                  | None ->
                    let length_none = Message.length ~raw:chan.raw msgs in
                    return (msgs, (Id.coll_of_string_opt ~mode ~length_none None))
                end
            end
          | Http_format.Plaintext ->
            let%lwt msgs = Message.of_stream ~format:write.http_format ~mode ~splitter:chan.splitter ~buffer_size:chan.buffer_size stream in
            let length_none = Message.length ~raw:chan.raw msgs in
            let ids = Id.coll_of_string_opt ~mode ~length_none id_header in
            return (msgs, ids)
        end
        in
        begin match parsed with
          | (_, Error str) -> return (Error [str])
          | (msgs, Ok ids) -> write_shared router ~listen_name ~chan ~write ~msgs ~ids
        end
    end

let write_zmq router ~listen_name ~chan_name ~ids ~msgs ~atomic =
  match find_chan router ~listen_name ~chan_name with
  | Error err -> return (Error [err])
  | Ok chan ->
    let open Channel in
    begin match chan.write with
      | None -> return (Error [sprintf "Channel [%s] doesn't support Writing to it" chan_name])
      | Some write ->
        let msgs = Message.of_string_coll ~atomic msgs in
        let ids = if Collection.is_empty ids then Id.coll_random (Message.length ~raw:chan.raw msgs) else ids in
        write_shared router ~listen_name ~chan ~write ~msgs ~ids
    end

(******************
   READ
 ******************)

let read_slice router ~listen_name ~chan_name ~mode ~limit =
  match find_chan router ~listen_name ~chan_name with
  | Error err -> return (Error [err])
  | Ok chan ->
    begin match chan.Channel.read with
      | None -> return (Error [sprintf "Channel [%s] doesn't support Reading from it" chan_name])
      | Some read ->
        let limit = begin match limit with
          | None -> Int64.max_value
          | Some x when Int64.is_non_positive x -> Int64.max_value
          | Some x -> x
        end
        in
        let%lwt slice = Channel.pull_slice chan ~mode ~limit ~only_once:read.Read_settings.only_once in
        async (fun () ->
          Logger.debug_lazy (lazy (
            sprintf "Read: (size: %d) [%s] from [%s]" (Collection.length slice.Persistence.payloads) chan_name listen_name
          ))
        );
        return (Ok (slice, chan))
    end

let read_stream router ~listen_name ~chan_name ~mode ~limit =
  match find_chan router ~listen_name ~chan_name with
  | Error err -> return (Error [err])
  | Ok chan ->
    begin match chan.Channel.read with
      | None -> return (Error [sprintf "Channel [%s] doesn't support Reading from it" chan_name])
      | Some read ->
        let limit = begin match limit with
          | None -> Int64.max_value
          | Some x when Int64.is_non_positive x -> Int64.max_value
          | Some x -> x
        end
        in
        let%lwt stream = Channel.pull_stream chan ~mode ~limit ~only_once:read.Read_settings.only_once in
        async (fun () ->
          Logger.debug_lazy (lazy (
            sprintf "Reading: [%s] (stream) from [%s]" chan_name listen_name
          ))
        );
        return (Ok (stream, chan))
    end

(******************
   COUNT
 ******************)

let count router ~listen_name ~chan_name ~mode =
  match find_chan router ~listen_name ~chan_name with
  | Error err -> return (Error [err])
  | Ok chan ->
    let%lwt count = Channel.size chan in
    async (fun () ->
      Logger.debug_lazy (lazy (
        sprintf "Counted: (size: %Ld) [%s] from [%s]" count chan_name listen_name
      ))
    );
    return (Ok count)

(******************
   DELETE
 ******************)

let delete router ~listen_name ~chan_name ~mode =
  match find_chan router ~listen_name ~chan_name with
  | Error err -> return (Error [err])
  | Ok chan ->
    begin match chan.Channel.emptiable with
      | false -> return (Error [sprintf "Channel [%s] doesn't support Deleting from it" chan_name])
      | true ->
        let%lwt () = Channel.delete chan in
        async (fun () ->
          Logger.debug_lazy (lazy (
            sprintf "Deleted: [%s] from [%s]" chan_name listen_name
          ))
        );
        return Result.ok_unit
    end

(******************
   HEALTH
 ******************)

let rec health router ~listen_name ~chan_name ~mode =
  match chan_name with

  (* Global health check *)
  | None ->
    let priv = Listener.(private_listener.id) in
    begin match String.Table.find router.table priv with
      | None -> fail_with "Cannot find internal private listener"
      | Some channels_table ->
        let channels = String.Table.data channels_table in
        let%lwt error_lists = Lwt_list.map_p (fun chan ->
            let chan_name = chan.Channel.name in
            let%lwt err = health router ~listen_name:priv ~chan_name:(Some chan_name) ~mode in
            return (List.map err ~f:(fun str -> sprintf "[%s] %s" chan_name str))
          ) channels
        in
        return (List.concat error_lists)
    end

  (* Channel health check *)
  | Some chan_name ->
    begin match find_chan router ~listen_name ~chan_name with
      | Error err -> return [err]
      | Ok chan ->
        let%lwt result = Channel.health chan in
        async (fun () ->
          Logger.debug_lazy (lazy (
            let str = match result with
              | [] -> "OK"
              | errors -> sprintf "Errors: %s" (String.concat ~sep:", " errors)
            in
            let printable_listen_name = if String.is_empty listen_name then "<global>" else listen_name in
            sprintf "Health: [%s] from [%s]. Status: %s" chan_name printable_listen_name str
          ))
        );
        return result
    end
