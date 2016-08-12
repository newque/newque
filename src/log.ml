open Core.Std
open Lwt

let outlog = Fs.log_dir ^ "out.log"
let errlog = Fs.log_dir ^ "err.log"

let stdout_logger = Lwt_log.channel ~close_mode:`Keep ~channel:Lwt_io.stdout ()
let stderr_logger = Lwt_log.channel ~close_mode:`Keep ~channel:Lwt_io.stderr ()
let stdout level str = Lwt_log.log ~logger:stdout_logger ~level str
let stderr level str = Lwt_log.log ~logger:stdout_logger ~level str

module type S = sig
  val debug : string -> unit t
  val info : string -> unit t
  val notice : string -> unit t
  val warning : string -> unit t
  val error : string -> unit t
  val fatal : string -> unit t
end

module type Settings = sig
  val path : string
end

module Make (Settings: Settings) : S = struct
  let path_logger = Lwt_log.file ~mode:`Append ~perm:Fs.default_perm ~file_name:Settings.path ()
  let path_and_out level str =
    let%lwt logger = path_logger in
    Lwt_log.log ~level ~logger str <&> stdout level str
  let path_and_err level str =
    let%lwt logger = path_logger in
    Lwt_log.log ~level ~logger str <&> stderr level str

  let debug = path_and_out Lwt_log.Debug
  let info = path_and_out Lwt_log.Info
  let notice = path_and_out Lwt_log.Notice
  let warning = path_and_err Lwt_log.Warning
  let error = path_and_err Lwt_log.Error
  let fatal = path_and_err Lwt_log.Fatal
end
