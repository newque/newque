open Core.Std
open Lwt
open Config_t

let parse_main path =
  try%lwt
    let%lwt contents = Lwt_io.chars_of_file path |> Lwt_stream.to_string in
    return (Config_j.config_newque_of_string contents)
  with
  | Ag_oj_run.Error str ->
    let%lwt _ = Log.stdout Lwt_log.Fatal str in
    failwith ("Error while parsing " ^ path)

let apply_main config watcher =
  (* Set global log level *)
  Lwt_log.reset_rules ();
  let level = match config.log_level with
    | Debug -> Lwt_log.Debug
    | Info -> Lwt_log.Info
    | Notice -> Lwt_log.Notice
    | Warning -> Lwt_log.Warning
    | Error -> Lwt_log.Error
    | Fatal -> Lwt_log.Fatal
  in
  Lwt_log.add_rule "*" level;
  Log.lazy_level := (Log.int_of_level level);
  (* TODO: dedup port and names *)
  Watcher.create_listeners watcher config.endpoints

(* TODO: dedup endpoints *)
let parse_channels path =
  let open Channel in
  let%lwt files = Fs.list_files path in
  Lwt_list.map_p (fun filename ->
      let fragments = String.split ~on:'.' filename in
      let () = if (List.length fragments < 2) || (List.last_exn fragments <> "json") then
          failwith (Printf.sprintf "Channel file %s must end in .json" filename) in

      let filepath = Printf.sprintf "%s%s" path filename in
      try%lwt
        let%lwt contents =
          (* TODO: make more efficient? *)
          Lwt_io.chars_of_file filepath
          |> Lwt_stream.to_string
        in
        let parsed = Config_j.config_channel_of_string contents in
        let name = List.slice fragments 0 (-1) |> String.concat ~sep:"." in
        return (Channel.create name parsed)
      with
      | Ag_oj_run.Error str ->
        let%lwt _ = Log.stdout Lwt_log.Fatal str in
        failwith (Printf.sprintf "Error while parsing %s" filepath)
    ) files

let apply_channels w channels =
  let open Result.Monad_infix in
  Router.register_listeners (Watcher.router w) (Watcher.listeners w)
  >>= fun () ->
  Router.register_channels (Watcher.router w) channels

let create_admin_server watcher config =
  let admin_spec_conf = {
    backlog = 5;
  } in
  let admin_conf = {
    name = "newque_admin";
    host = config.admin.a_host;
    port = config.admin.a_port;
    settings = Http_proto admin_spec_conf;
  } in
  let%lwt admin_server = Http.start admin_conf admin_spec_conf `Admin in
  let (_, wakener) = wait () in
  let open Listener in
  async (fun () -> Watcher.monitor watcher {id = admin_conf.name; server = HTTP (admin_server, wakener);});

  let success_str = Printf.sprintf "Started Admin server on HTTP %s:%d" admin_conf.host admin_conf.port in
  return (admin_server, success_str)
