open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog end)

type t = {
  table: Channel.t list String.Table.t; (* Channels per listener.name *)
}

let create (listeners: Watcher.listener list) =
  let open Watcher in
  let table = String.Table.create ~size:5 () in
  List.iter listeners ~f:(fun listen ->
      ignore (String.Table.add table ~key:listen.id ~data:[])
    );
  {table}

let register_channels router (channels: Channel.t list) =
  let open Channel in
  List.map channels ~f:(fun chan ->
      List.map chan.endpoint_names ~f:(fun endp ->
          match String.Table.find router.table endp with
          | Some ll -> Ok ()
          | None -> Error (Printf.sprintf "Cannot add channel %s to %s. Does that listener exist?" chan.name endp)
          (* String.Table.set router.table ~key:chan.name ~data:new_entry; *)
        ))

let route msg = ()
