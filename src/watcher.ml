open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog end)

type listener =
  | HTTP of Http.t * unit Lwt.u
  | ZMQ of unit * unit Lwt.u

type t = {
  listeners: listener Int.Table.t;
}

let create () = { listeners = Int.Table.create ~size:5 (); }

let monitor server = match server with
  | HTTP (http, wakener) ->
    let open Http in
    let%lwt result = begin try%lwt
        let%lwt () = choose [http.thread; waiter_of_wakener wakener; waiter_of_wakener http.close] in
        return Result.ok_unit
      with
      | Unix.Unix_error (code, name, param) -> return (Result.fail (Fs.format_unix_exn code name param))
      | ex -> return (Result.fail (Exn.to_string ex))
    end in
    Result.iter_error ~f:(fun err -> async (fun () -> Logger.error err)) result;
    begin match result with
      | Error _ | Ok () when not (is_sleeping http.thread) -> return_unit
      (* Restart the server and monitor it recursively, with a restart timeout *)
      | Ok () -> return_unit
      (* Just stop monitoring it *)
    end
  | ZMQ (zmq, wakener) -> failwith "Unimplemented"

let add_listeners watcher config =
  let open Config_j in
  let%lwt ll = Lwt_list.map_p (fun ext ->
      (* Stop and replace possible existing listener on the same port *)
      let%lwt () = match Int.Table.find_and_remove watcher.listeners ext.port with
        | Some (HTTP (existing, _)) -> Http.stop existing
        | Some (ZMQ (existing, _)) -> failwith "Unimplemented"
        | None -> return_unit
      in
      let%lwt started = match ext.settings with
        | Http_proto settings ->
          let%lwt () = Logger.notice (Printf.sprintf "Starting HTTP on %s:%s" ext.host (Int.to_string ext.port)) in
          let%lwt http = Http.start ext settings in
          let (_, wakener) = wait () in
          return (HTTP (http, wakener))
        | Zmq_proto settings -> failwith "Unimplemented"
      in
      async (fun () -> monitor started);
      Int.Table.add_exn watcher.listeners ~key:ext.port ~data:started;
      return_unit
    ) config.endpoints in
  Int.Table.keys watcher.listeners |> List.sexp_of_t Int.sexp_of_t |> Sexp.to_string |> print_endline;
  return_unit

let welp watcher =
  let http = match Int.Table.find watcher.listeners 9000 with
    | Some (HTTP (http, _)) -> http
    | _ -> failwith "Derp"
  in
  let open Http in
  print_endline "before";

  let%lwt () = Lwt_unix.sleep 5. in

  (* let%lwt () = Http.close http in *)
  cancel http.thread;

  print_endline "cancelled";

  return_unit
