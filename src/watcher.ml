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

let rec monitor server = match server with
  | HTTP (http, wakener) ->
    let open Http in
    let must_restart = begin try%lwt
        let%lwt () = choose [http.thread; waiter_of_wakener wakener; waiter_of_wakener http.close] in
        if not (is_sleeping http.thread) then return_true else return_false
      with
      | Unix.Unix_error (code, name, param) ->
        let%lwt () = Logger.error (Fs.format_unix_exn code name param) in
        return_true
      | ex ->
        let%lwt () = Logger.error (Exn.to_string ex) in
        return_true
    end in
    begin match%lwt must_restart with
      | false -> return_unit (* Just stop monitoring it *)
      | true ->
        (* Restart the server and monitor it recursively *)
        let g = http.generic in
        let open Config_j in
        let%lwt () = Printf.sprintf "Restarting HTTP listener %s on HTTP %s:%s" g.name g.host (Int.to_string g.port)
                     |> Logger.notice in
        let%lwt () = Http.close http in
        let%lwt restarted = Http.start http.generic http.specific in
        let (_, new_wakener) = wait () in
        monitor (HTTP (restarted, new_wakener))
    end
  | ZMQ (zmq, wakener) -> failwith "Unimplemented"

let add_listeners watcher config =
  let open Config_j in
  let%lwt ll = Lwt_list.map_p (fun generic ->
      (* Stop and replace possible existing listener on the same port *)
      let%lwt () = match Int.Table.find_and_remove watcher.listeners generic.port with
        | Some (HTTP (existing, _)) -> Http.stop existing
        | Some (ZMQ (existing, _)) -> failwith "Unimplemented"
        | None -> return_unit
      in
      let%lwt started = match generic.settings with
        | Http_proto specific ->
          let%lwt () = Logger.notice (Printf.sprintf "Starting %s on HTTP %s:%s" generic.name generic.host (Int.to_string generic.port)) in
          let%lwt http = Http.start generic specific in
          let (_, wakener) = wait () in
          return (HTTP (http, wakener))
        | Zmq_proto specific -> failwith "Unimplemented"
      in
      async (fun () -> monitor started);
      Int.Table.add_exn watcher.listeners ~key:generic.port ~data:started;
      return_unit
    ) config.endpoints in
  Int.Table.keys watcher.listeners |> List.sexp_of_t Int.sexp_of_t |> Sexp.to_string |> print_endline;
  return_unit
