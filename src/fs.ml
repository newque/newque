open Core.Std
open Lwt

let default_perm = 0o755 (* rwxr-xr-x *)
let log_dir = "./logs/"
let log_chan_dir = "./logs/channels/"
let conf_dir = "./conf/"
let conf_chan_dir = "./conf/channels/"

(* | Unix.Unix_error (c, n, p) -> return (Error (Logger.format_unix_exn c n p)) *)
let format_unix_exn code name param =
  Printf.sprintf "%s {syscall: %s(%s)}" (String.uppercase (Unix.error_message code)) name param

let is_directory ?(create = false) path =
  try%lwt
    let%lwt stats = Lwt_unix.stat path in
    let open Lwt_unix in
    begin match stats.st_kind with
      | S_DIR -> return_true
      | S_REG | S_CHR | S_BLK | S_LNK | S_FIFO | S_SOCK -> return_false
    end with
  | Unix.Unix_error (Unix.ENOENT, _, _) when create ->
    let%lwt () = Lwt_unix.mkdir path default_perm in return_true
  | Unix.Unix_error (Unix.ENOENT, _, _) -> return_false

let list_files path =
  Lwt_unix.files_of_directory path
  |> Lwt_stream.filter_s (fun file ->
      let%lwt stats = Lwt_unix.stat (path ^ file) in
      let open Lwt_unix in
      match stats.st_kind with
      | S_REG -> return_true
      | S_DIR | S_CHR | S_BLK | S_LNK | S_FIFO | S_SOCK -> return_false
    )
  |> Lwt_stream.to_list
