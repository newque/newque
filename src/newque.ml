#ifdef DEBUG
  Printexc.record_backtrace true
  #endif

open Core.Std
open Lwt
open Http

let () = Lwt_engine.set ~transfer:true ~destroy:true (new Lwt_engine.libev)
let () = Lwt.async_exception_hook := fun ex -> print_endline ("UNCAUGHT EXCEPTION: " ^ (Exn.to_string ex))
let () = Lwt_preemptive.init 4 25 (fun str -> ignore (async (fun () -> Log.stdout Lwt_log.Info str)))

(* Only for startup, replaced by newque.json settings later *)
let () = Lwt_log.add_rule "*" Lwt_log.Debug

let start config_path =
  let%lwt () = Log.stdout Lwt_log.Info "Starting Newque" in
  (* Make directories for logs and channels *)
  let check_directory path =
    let dir = Fs.is_directory ~create:true path in
    if%lwt dir then return_unit else
      Log.stderr Lwt_log.Error (path ^ " is not a directory or can't be created as one")
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
  let%lwt () = match result with
    | Ok () ->
      Printf.sprintf "Current router state: %s"
        (Watcher.router watcher |> Router.sexp_of_t |> Util.string_of_sexp)
      |> Logger.info
    | Error ll ->
      String.concat ~sep:", " ll
      |> Logger.error
  in

  let%lwt () = admin_server.thread in
  Logger.fatal "Admin server thread terminated."

let _ =
  Lwt_unix.run (start (Fs.conf_dir ^ "newque.json"))
