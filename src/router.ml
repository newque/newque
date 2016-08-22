open Core.Std
open Lwt
open Sexplib.Conv

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

let return_ok_one = return (Ok 1)
let publish router ~listen_name ~chan_name ~mode stream =
  match String.Table.find router.table listen_name with
  | None -> return (Error (400, [Printf.sprintf "Unknown listener \'%s\'" listen_name]))
  | Some chan_table ->
    begin match String.Table.find chan_table chan_name with
      | None -> return (Error (400, [Printf.sprintf "No channel \'%s\' associated with listener \'%s\'" chan_name listen_name]))
      | Some chan ->
        let open Channel in
        begin match mode with
          | `Single ->
            let%lwt msg = Message.of_stream ~buffer_size:chan.buffer_size stream in
            let%lwt () = Channel.push_single chan msg in
            return_ok_one
          | `Multiple ->
            let%lwt msgs = Message.list_of_stream ~sep:chan.separator stream in
            let%lwt () = join (List.map ~f:(fun msg -> Channel.push_single chan msg) msgs) in
            return (Ok (List.length msgs))
          | `Atomic ->
            let%lwt msgs = Message.list_of_stream ~sep:chan.separator stream in
            let%lwt () = Channel.push_atomic chan msgs in
            return (Ok (List.length msgs))
        end
    end

let fetch router chan_name =
  return (Ok ())
