open Core.Std
open Lwt
open Config_t

let parse_main path =
  let parse path =
    let%lwt contents = Lwt_io.chars_of_file path |> Lwt_stream.to_string in
    return (Config_j.config_newque_of_string contents)
  in
  try%lwt
    Util.parse_async_bind parse path
  with
  | Failure err ->
    let str = sprintf "Error while parsing %s: %s" path err in
    let%lwt () = Log.stdout Lwt_log.Fatal str in
    fail_with str

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
  Watcher.create_listeners watcher config.endpoints

let parse_channels config path =
  let open Channel in
  let%lwt files = Fs.list_files path in
  Lwt_list.map_p (fun filename ->
    let fragments = String.split ~on:'.' filename in
    let%lwt () = if (List.length fragments < 2) || (List.last_exn fragments <> "json")
      then fail_with (sprintf "Channel file %s must end in .json" filename)
      else return_unit
    in
    let filepath = sprintf "%s%s" path filename in
    let%lwt contents = Lwt_stream.to_string (Lwt_io.chars_of_file filepath) in
    let mapper = fun str ->
      let parsed = Config_j.config_channel_of_string str in
      let name = List.slice fragments 0 (-1) |> String.concat ~sep:"." in
      Channel.create name parsed
    in
    try%lwt
      Util.parse_async_bind mapper contents
    with
    | Failure err ->
      let%lwt () = Log.stdout Lwt_log.Fatal err in
      fail_with (sprintf "Error while parsing %s: %s" filepath err)
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
    protocol_settings = Config_http_prot admin_spec_conf;
  } in
  let%lwt admin_server =
    let open Routing in
    let table = (Watcher.router watcher).Router.table in
    let admin = Admin { table } in
    Http_prot.start admin_conf admin_spec_conf admin
  in
  let (_, wakener) = wait () in
  let open Listener in
  async (fun () -> Watcher.monitor watcher {id = admin_conf.name; server = HTTP (admin_server, wakener);});

  let success_str = sprintf "Started Admin server on HTTP %s:%d" admin_conf.host admin_conf.port in
  return (admin_server, success_str)
