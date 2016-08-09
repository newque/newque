Printexc.record_backtrace true

open Core.Std
open Lwt
open Http

let () = Lwt_engine.set ~transfer:true ~destroy:true (new Lwt_engine.libev)
let () = Lwt.async_exception_hook := fun ex -> print_endline ("UNCAUGHT EXCEPTION: " ^ (Exn.to_string ex))
let () = Lwt_log.add_rule "*" Lwt_log.Debug

let start config_path =
  (* Make directories for logs and channels *)
  let check_directory path =
    let dir = Fs.is_directory ~create:true path in
    if%lwt dir then return_unit else
      Log.stderr Lwt_log.Error (path ^ " is not a directory or can't be created as one")
  in
  let%lwt () = Lwt_list.iter_s check_directory [Fs.log_dir; Fs.log_chan_dir; Fs.conf_dir; Fs.conf_chan_dir] in

  (* Make logger *)
  let module Logger = Log.Make (struct let path = Log.outlog end) in

  (* Load main config *)
  let%lwt () = Logger.info ("Starting Newque") in
  let%lwt () = Logger.info ("Loading " ^ config_path) in
  let%lwt config = Config.parse_main config_path in
  (* let watcher = Watcher.create () in *)
  Config.apply_main config;

  (* Load channel config files *)
  let%lwt channels = Config.parse_channels Fs.conf_chan_dir in
  let generic = config.listeners |> List.hd_exn in
  let (Config_j.HTTP http) = generic.settings in
  let%lwt server = Http.start generic http in
  print_endline "started";
  let%lwt () = Lwt_unix.sleep 5. in
  print_endline "closing";
  let%lwt () = Http.stop server in
  print_endline "closed";
  let%lwt () = Lwt_unix.sleep 5. in
  print_endline "reopening";
  let%lwt server = Http.start generic http in
  print_endline "reopened!!!!!";
  let%lwt () = Lwt_unix.sleep 5. in
  return_unit

let _ =
  Lwt_unix.run (start (Fs.conf_dir ^ "newque.json"))
