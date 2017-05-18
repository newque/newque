#ifdef DEBUG
  Printexc.record_backtrace true
  #endif

let newque_version = "0.0.4"

open Core
open Lwt
open Http_prot

let () = Lwt_engine.set ~transfer:true ~destroy:true (new Lwt_engine.libev ())

let () = Lwt.async_exception_hook := fun ex ->
    print_endline (sprintf "UNCAUGHT EXCEPTION: %s" (Exception.full ex))

let () = Lwt_preemptive.init 4 25 (fun str ->
    async (fun () ->
      print_endline (sprintf "*** THREAD POOL *** %s" str);
      return_unit
    )
  )

(* Only for startup, replaced by newque.json settings later *)
let () = Lwt_log.add_rule "*" Lwt_log.Debug

let start config_path =
  let%lwt () = Log.write_stdout Lwt_log.Info (sprintf "Starting Newque %s" newque_version) in
  (* Make directories for logs and channels *)
  let check_directory path =
    let dir = Fs.is_directory ~create:true path in
    if%lwt dir then return_unit else
      Log.write_stderr Lwt_log.Error (sprintf "%s is not a directory or can't be created as one" path)
  in
  let%lwt () = Lwt_list.iter_s check_directory [
      Fs.log_dir;
      Fs.conf_dir;
      Fs.conf_chan_dir;
      Fs.data_dir;
      Fs.data_chan_dir;
    ]
  in

  (* Make logger *)
  Log.init ();
  let module Logger = Log.Make (struct let section = "Main" end) in

  (* Load main config *)
  let%lwt () = Logger.info (sprintf "Loading [%s]" config_path) in
  let%lwt config = Configtools.parse_main config_path in
  let log_level_str =
    let open Config_t in
    config.log_level
    |> Log.log_level_of_variant
    |> Lwt_log.string_of_level
  in
  let%lwt () = Logger.info (sprintf "Active Log Level: [%s]" log_level_str) in
  let watcher = Watcher.create () in
  let%lwt () = Configtools.apply_main config watcher in

  (* Create admin server *)
  let%lwt (_, success_str) = Watcher.create_admin_server watcher config in
  let%lwt () = Logger.info success_str in

  (* Load channel config files *)
  let%lwt channels = Configtools.parse_channels config Fs.conf_chan_dir in
  let result = Configtools.apply_channels watcher channels in
  match result with
  | Error errors ->
    Logger.error (String.concat ~sep:", " errors)
  | Ok () ->
    let router = Watcher.router watcher in
    let priv = Listener.(private_listener.id) in
    let%lwt () = Logger.info "Running global health check..." in
    try%lwt
      match%lwt Router.health router ~listen_name:priv ~chan_name:None ~mode:`Health with
      | (_::_) as errors ->
        Logger.error (String.concat ~sep:"\n" errors)
      | [] ->
        let%lwt () = Logger.info "Global health check succeeded" in
        let%lwt () = Logger.info "*** SERVER STARTED ***" in
        let listeners_json = Watcher.listeners_to_json watcher None in
        print_endline (Yojson.Basic.pretty_to_string listeners_json);
        (* Run forever *)
        fst (wait ())
    with
    | ex ->
      Logger.fatal (sprintf
          "Critical failure during startup process.\nCould not complete Global Health Check.\n%s"
          (Exception.full ex)
      )


let _ =
  try
    Lwt_main.run (start (sprintf "%s%s" Fs.conf_dir "newque.json"))
  with
  | ex ->
    print_endline (sprintf
        "\n\nCritical failure during startup process.\n%s"
        (Exception.full ex)
    )
