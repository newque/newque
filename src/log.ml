open Core
open Lwt

let log_level_of_variant variant =
  match variant with
  | `Debug -> Lwt_log.Debug
  | `Info -> Lwt_log.Info
  | `Notice -> Lwt_log.Notice
  | `Warning -> Lwt_log.Warning
  | `Error -> Lwt_log.Error
  | `Fatal -> Lwt_log.Fatal

let int_of_level level =
  match level with
  | Lwt_log.Debug -> 1
  | Lwt_log.Info -> 2
  | Lwt_log.Notice -> 3
  | Lwt_log.Warning -> 4
  | Lwt_log.Error -> 5
  | Lwt_log.Fatal -> 6

let outfile = sprintf "%s%s" Fs.log_dir "out.log"
let errfile = sprintf "%s%s" Fs.log_dir "err.log"

let template = match Sys.getenv "NEWQUE_ENV" with
  | None -> "$(date) [$(level)] [$(section)]: $(message)"
  | Some env -> sprintf "$(date) [$(level)] [%s] [$(section)]: $(message)" env

let lazy_level = ref (int_of_level Lwt_log.Debug)
let init_thread, init_wakener = wait ()

let init () =
  wakeup init_wakener ()

let outfile_logger =
  let%lwt () = init_thread in
  Lwt_log.file ~template ~mode:`Append ~perm:Fs.default_perm ~file_name:outfile ()

let errfile_logger =
  let%lwt () = init_thread in
  Lwt_log.file ~template ~mode:`Append ~perm:Fs.default_perm ~file_name:errfile ()

let stdout_logger = Lwt_log.channel ~template ~close_mode:`Keep ~channel:Lwt_io.stdout ()
let stderr_logger = Lwt_log.channel ~template ~close_mode:`Keep ~channel:Lwt_io.stderr ()

let default_section = Lwt_log.Section.make ""

let write_stdout ?(section=default_section) level str =
  Lwt_log.log ~section ~logger:stdout_logger ~level str

let write_stderr ?(section=default_section) level str =
  Lwt_log.log ~section ~logger:stderr_logger ~level str

let write_out ~section level str =
  let%lwt logger = outfile_logger in
  Lwt_log.log ~section ~logger ~level str <&> write_stdout ~section level str

let write_err ~section level str =
  let%lwt logger = errfile_logger in
  Lwt_log.log ~section ~logger ~level str <&> write_stderr ~section level str

type simple_logging = string -> unit Lwt.t
type lazy_logging = string Lazy.t -> unit Lwt.t

module type S = sig
  val debug : simple_logging
  val info : simple_logging
  val notice : simple_logging
  val warning : simple_logging
  val error : simple_logging
  val fatal : simple_logging

  val debug_lazy : lazy_logging
  val info_lazy : lazy_logging
  val notice_lazy : lazy_logging
  val warning_lazy : lazy_logging
  val error_lazy : lazy_logging
  val fatal_lazy : lazy_logging
end

module type Argument = sig
  val section : string
end

module Make (Argument: Argument) : S = struct
  let section = Lwt_log.Section.make Argument.section

  let out_lazy level str =
    if (int_of_level level) < (!lazy_level)
    then return_unit
    else write_out ~section level (Lazy.force str)

  let err_lazy level str =
    if (int_of_level level) < (!lazy_level)
    then return_unit
    else write_err ~section level (Lazy.force str)

  let debug = write_out ~section Lwt_log.Debug
  let info = write_out ~section Lwt_log.Info
  let notice = write_out ~section Lwt_log.Notice
  let warning = write_err ~section Lwt_log.Warning
  let error = write_err ~section Lwt_log.Error
  let fatal = write_err ~section Lwt_log.Fatal

  let debug_lazy = out_lazy Lwt_log.Debug
  let info_lazy = out_lazy Lwt_log.Info
  let notice_lazy = out_lazy Lwt_log.Notice
  let warning_lazy = err_lazy Lwt_log.Warning
  let error_lazy = err_lazy Lwt_log.Error
  let fatal_lazy = err_lazy Lwt_log.Fatal
end
