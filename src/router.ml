open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Router" end)

type t = {
  table: Channel.t String.Table.t String.Table.t; (* Channels (accessed by name) by listener.id *)
} [@@deriving sexp]

let create () =
  let table = String.Table.create ~size:5 () in
  {table}

let register_listeners router listeners =
  let open Listener in
  List.filter_map listeners ~f:(fun listen ->
      let entry = String.Table.create ~size:5 () in
      match String.Table.add router.table ~key:listen.id ~data:entry with
      | `Ok -> None
      | `Duplicate -> Some (Printf.sprintf "Cannot register listener %s because it already exists" listen.id)
    )
  |> fun ll -> if List.length ll = 0 then Ok () else Error ll

(* Important: At this time, listeners must exist prior to adding channels *)
let register_channels router channels =
  let open Channel in
  List.concat_map channels ~f:(fun chan ->
      List.filter_map chan.endpoint_names ~f:(fun listen_name ->
          match String.Table.find router.table listen_name with
          | Some chan_table ->
            begin match String.Table.add chan_table ~key:chan.name ~data:chan with
              | `Ok -> None
              | `Duplicate -> Some (
                  Printf.sprintf
                    "Registered channel %s with listener %s but another channel with the same name already existed"
                    chan.name listen_name
                )
            end
          | None -> Some (Printf.sprintf "Cannot add channel %s to %s. Does that listener exist?" chan.name listen_name)
        ))
  |> function
  | [] -> Ok ()
  | errors -> Error errors

let find_chan router ~listen_name ~chan_name =
  match String.Table.find router.table listen_name with
  | None -> Error [Printf.sprintf "Unknown listener \'%s\'" listen_name]
  | Some chan_table ->
    begin match String.Table.find chan_table chan_name with
      | None -> Error [Printf.sprintf "No channel \'%s\' associated with listener \'%s\'" chan_name listen_name]
      | Some chan -> Ok chan
    end

let write router ~listen_name ~chan_name ~id_header ~mode stream =
  match find_chan router ~listen_name ~chan_name with
  | (Error _) as err -> return err
  | Ok chan ->
    let open Channel in
    let%lwt msgs = Message.of_stream ~mode ~sep:chan.separator ~buffer_size:chan.buffer_size stream in
    begin match Id.rev_list_of_header ~mode ~msgs id_header with
      | Error str -> return (Error [str])
      | Ok ids ->
        let%lwt count = Channel.push chan msgs ids in
        ignore_result (Logger.debug_lazy (lazy (
            Printf.sprintf "Wrote: %s (length: %d) %s from %s" (Mode.Write.to_string mode) count chan_name listen_name
          )));
        return (Ok count)
    end

let read router ~listen_name ~chan_name ~id_header ~mode = return (Ok ())

let count router ~listen_name ~chan_name ~(mode: Mode.Count.t) =
  match find_chan router ~listen_name ~chan_name with
  | (Error _) as err -> return err
  | Ok chan ->
    let%lwt count = Channel.size chan () in
    ignore_result (Logger.debug_lazy (lazy (
        Printf.sprintf "Counted: %s (size: %d) from %s" chan_name count listen_name
      )));
    return (Ok count)
