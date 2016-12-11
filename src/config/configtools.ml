open Core.Std
open Lwt
open Config_t

let parse_main path =
  try%lwt
    let%lwt contents = Lwt_io.chars_of_file path |> Lwt_stream.to_string in
    return (Config_j.config_newque_of_string contents)
  with
  | ex ->
    let failure, stack = Exception.human_bt ex in
    let str = sprintf "[%s] %s" path failure in
    let%lwt () = Log.stdout Lwt_log.Fatal (sprintf "%s\n%s" str stack) in
    fail_with str

let apply_main config watcher =
  (* Set global log level *)
  Lwt_log.reset_rules ();
  let level = Log.log_level_of_variant config.log_level in
  Lwt_log.add_rule "*" level;
  Log.lazy_level := (Log.int_of_level level);
  Watcher.create_listeners watcher config.endpoints

let parse_channels config path =
  let open Channel in
  let%lwt files = Fs.list_files path in
  Lwt_list.map_p (fun filename ->
    let fragments =
      String.split ~on:'.' filename
      |> List.filter ~f:(fun str -> String.is_empty str |> not)
    in
    let%lwt () = if (List.length fragments < 2) || (List.last_exn fragments <> "json")
      then fail_with (sprintf "Channel file %s must end in .json" filename)
      else return_unit
    in
    let filepath = sprintf "%s%s" path filename in
    let%lwt contents = Lwt_stream.to_string (Lwt_io.chars_of_file filepath) in
    try%lwt
      let parsed = Config_j.config_channel_of_string contents in
      let name = List.slice fragments 0 (-1) |> String.concat ~sep:"." in
      Channel.create name parsed
    with
    | ex ->
      let failure, stack = Exception.human_bt ex in
      let str = sprintf "[%s] %s" filepath failure in
      let%lwt () = Log.stdout Lwt_log.Fatal (sprintf "%s\n%s" str stack) in
      fail_with str
  ) files

let apply_channels w channels =
  let open Result.Monad_infix in
  Router.register_listeners (Watcher.router w) (Watcher.listeners w)
  >>= fun () ->
  Router.register_channels (Watcher.router w) channels
