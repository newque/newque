open Core.Std
open Lwt
open Config_j

module Logger = Log.Make (struct let path = Log.outlog end)

let parse_main path =
  try%lwt
    let%lwt contents = Lwt_io.chars_of_file path |> Lwt_stream.to_string in
    return (config_of_string contents)
  with
  | Ag_oj_run.Error str ->
    let%lwt _ = Log.stdout Lwt_log.Info str in
    failwith ("Error while parsing " ^ path)

let apply_main config watcher =
  (* Set global log level *)
  Lwt_log.reset_rules ();
  begin match config.log_level with
    | Debug -> Lwt_log.Debug
    | Info -> Lwt_log.Info
    | Notice -> Lwt_log.Notice
    | Warning -> Lwt_log.Warning
    | Error -> Lwt_log.Error
    | Fatal -> Lwt_log.Fatal end
  |> Lwt_log.add_rule "*";
  (* Start listeners *)
  Watcher.add_listeners watcher config
(* TODO: dedup port and names *)

(* TODO: dedup endpoints *)
let parse_channels path =
  let%lwt files = Fs.list_files path in
  Lwt_list.map_p (fun filename ->
      let fragments = String.split ~on:'.' filename in
      let () = if (List.length fragments < 2) || (List.last_exn fragments <> "json") then
          failwith (Printf.sprintf "Channel file %s must end in .json" filename) in

      let name = List.slice fragments 0 (-1) |> String.concat ~sep:"." in
      let%lwt contents = Lwt_io.chars_of_file (path ^ filename)
                         |> Lwt_stream.to_string in

      return (name, channel_of_string contents)
    ) files
