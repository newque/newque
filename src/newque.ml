#ifdef DEBUG
  Printexc.record_backtrace true
  #endif

open Core.Std
open Lwt
open Http_prot

let () = Lwt_engine.set ~transfer:true ~destroy:true (new Lwt_engine.libev)
let () = Lwt.async_exception_hook := fun ex ->
    let str = match ex with
      | Failure str -> str
      | ex -> Exn.to_string ex
    in
    print_endline (sprintf "UNCAUGHT EXCEPTION: %s" str
    )
let () = Lwt_preemptive.init 4 25 (fun str -> async (fun () -> Log.stdout Lwt_log.Info str))

(* Only for startup, replaced by newque.json settings later *)
let () = Lwt_log.add_rule "*" Lwt_log.Debug

let start config_path =
  let%lwt () = Log.stdout Lwt_log.Info "Starting Newque" in
  (* Make directories for logs and channels *)
  let check_directory path =
    let dir = Fs.is_directory ~create:true path in
    if%lwt dir then return_unit else
      Log.stderr Lwt_log.Error (sprintf "%s is not a directory or can't be created as one" path)
  in
  let%lwt () = Lwt_list.iter_s check_directory [
      Fs.log_dir;
      Fs.log_chan_dir;
      Fs.conf_dir;
      Fs.conf_chan_dir;
      Fs.data_dir;
      Fs.data_chan_dir;
    ] in

  (* Make logger *)
  let module Logger = Log.Make (struct let path = Log.outlog let section = "Main" end) in

  (* Load main config *)
  let%lwt () = Logger.info ("Loading " ^ config_path) in
  let%lwt config = Configtools.parse_main config_path in
  let watcher = Watcher.create () in
  let%lwt () = Configtools.apply_main config watcher in

  (* Create admin server *)
  let%lwt (admin_server , success_str) = Configtools.create_admin_server watcher config in
  let%lwt () = Logger.info success_str in

  (* Load channel config files *)
  let%lwt channels = Configtools.parse_channels config Fs.conf_chan_dir in
  let result = Configtools.apply_channels watcher channels in
  match result with
  | Error errors ->
    Logger.error (String.concat ~sep:", " errors)
  | Ok () ->
    let open Router in
    let router = Watcher.router watcher in
    let priv = Listener.(private_listener.id) in
    let%lwt () = Logger.info "Running global health check..." in
    match%lwt Router.health router ~listen_name:priv ~chan_name:None ~mode:`Health with
    | (_::_) as errors ->
      Logger.error (String.concat ~sep:", " errors)
    | [] ->
      let%lwt () = Logger.info "Global health check succeeded" in
      let%lwt () = Logger.info "Server started" in
      let pairs = List.map (Int.Table.to_alist (Watcher.table watcher)) ~f:(fun (port, listener) ->
          let name = listener.Listener.id in
          let channels = match String.Table.find router.table name with
            | None -> []
            | Some chan_table -> String.Table.keys chan_table
          in
          name, `Assoc [
            "protocol", `String (Listener.get_prot listener);
            "port", `Int port;
            "channels", `List (List.map channels ~f:(fun s -> `String s))
          ]
        )
      in
      print_endline (Yojson.Basic.pretty_to_string (`Assoc pairs));
      (* Run forever *)
      fst (wait ())


let _ =
  Lwt_unix.run (start (Fs.conf_dir ^ "newque.json"))
