open Core.Std
open Lwt

let outlog = Fs.log_dir ^ "out.log"
let errlog = Fs.log_dir ^ "err.log"

let int_of_level level =
  match level with
  | Lwt_log.Debug -> 1
  | Lwt_log.Info -> 2
  | Lwt_log.Notice -> 3
  | Lwt_log.Warning -> 4
  | Lwt_log.Error -> 5
  | Lwt_log.Fatal -> 6

(* Yes, this is a hack. It's the current Log Level,
   that lazy logging uses to decide whether to build a
   log string or not. *)
let lazy_level = ref (int_of_level Lwt_log.Info)

let default_section = Lwt_log.Section.make "--- "

let stdout_logger = Lwt_log.channel ~close_mode:`Keep ~channel:Lwt_io.stdout ()
let stderr_logger = Lwt_log.channel ~close_mode:`Keep ~channel:Lwt_io.stderr ()

let stdout ?(section=default_section) level str = Lwt_log.log ~section ~logger:stdout_logger ~level str
let stderr ?(section=default_section) level str = Lwt_log.log ~section ~logger:stdout_logger ~level str

module type S = sig
  val debug : string -> unit t
  val info : string -> unit t
  val notice : string -> unit t
  val warning : string -> unit t
  val error : string -> unit t
  val fatal : string -> unit t

  val debug_lazy : string Lazy.t -> unit t
  val info_lazy : string Lazy.t -> unit t
  val notice_lazy : string Lazy.t -> unit t
  val warning_lazy : string Lazy.t -> unit t
  val error_lazy : string Lazy.t -> unit t
  val fatal_lazy : string Lazy.t -> unit t
end

module type Argument = sig
  val path : string
  val section : string
end

module Make (Argument: Argument) : S = struct
  let section = Lwt_log.Section.make Argument.section
  let path_logger = lazy (Lwt_log.file ~mode:`Append ~perm:Fs.default_perm ~file_name:Argument.path ())

  let path_and_out level str =
    let%lwt logger = Lazy.force path_logger in
    Lwt_log.log ~section ~level ~logger str <&> stdout ~section level str

  let path_and_err level str =
    let%lwt logger = Lazy.force path_logger in
    Lwt_log.log ~section ~level ~logger str <&> stderr ~section level str

  let debug = path_and_out Lwt_log.Debug
  let info = path_and_out Lwt_log.Info
  let notice = path_and_out Lwt_log.Notice
  let warning = path_and_err Lwt_log.Warning
  let error = path_and_err Lwt_log.Error
  let fatal = path_and_err Lwt_log.Fatal

  let path_and_out_lazy level str =
    if (int_of_level level) < (!lazy_level) then return_unit else
      let str = Lazy.force str in
      let%lwt logger = Lazy.force path_logger in
      Lwt_log.log ~section ~level ~logger str <&> stdout ~section level str

  let path_and_err_lazy level str =
    if (int_of_level level) < (!lazy_level) then return_unit else
      let str = Lazy.force str in
      let%lwt logger = Lazy.force path_logger in
      Lwt_log.log ~section ~level ~logger str <&> stderr ~section level str

  let debug_lazy = path_and_out_lazy Lwt_log.Debug
  let info_lazy = path_and_out_lazy Lwt_log.Info
  let notice_lazy = path_and_out_lazy Lwt_log.Notice
  let warning_lazy = path_and_out_lazy Lwt_log.Warning
  let error_lazy = path_and_out_lazy Lwt_log.Error
  let fatal_lazy = path_and_out_lazy Lwt_log.Fatal
end
