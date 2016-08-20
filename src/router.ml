open Core.Std
open Lwt
open Sexplib.Conv

module Logger = Log.Make (struct let path = Log.outlog end)

type t = {
  table: Channel.t list String.Table.t; (* Channels by listener.id *)
} [@@deriving sexp]

let create () =
  let table = String.Table.create ~size:5 () in
  {table}

let register_listeners router listeners =
  let open Listener in
  List.filter_map listeners ~f:(fun listen ->
      match String.Table.add router.table ~key:listen.id ~data:[] with
      | `Ok -> None
      | `Duplicate -> Some (Printf.sprintf "Cannot register listener %s because it already exists" listen.id)
    )
  |> fun ll -> if List.length ll = 0 then Ok () else Error ll

(* Important: At this time, listeners must exist prior to adding channels *)
let register_channels router channels =
  let open Channel in
  List.concat_map channels ~f:(fun chan ->
      List.filter_map chan.endpoint_names ~f:(fun endp ->
          match String.Table.find router.table endp with
          | Some chan_list ->
            let register data = String.Table.set router.table ~key:endp ~data in
            begin match List.partition_tf chan_list ~f:(fun a -> a.name = chan.name) with
              | (((_::_) as dup), rest) ->
                register (chan::rest);
                Some (
                  Printf.sprintf
                    "Registered channel %s with listener %s but the following channel(s) with the same name were replaced: %s"
                    chan.name endp (List.sexp_of_t Channel.sexp_of_t dup |> Sexp.to_string)
                )
              | ([], rest) -> register (chan::rest); None
            end
          | None -> Some (Printf.sprintf "Cannot add channel %s to %s. Does that listener exist?" chan.name endp)
        ))
  |> function
  | [] -> Ok ()
  | errors -> Error errors

let route_msg router chan_name msg = return (Ok ())

let route_atomic router chan_name msgs = return (Ok ())
