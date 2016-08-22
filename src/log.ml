open Core.Std
open Lwt

let outlog = Fs.log_dir ^ "out.log"
let errlog = Fs.log_dir ^ "err.log"

let default_section = Lwt_log.Section.make "--- "
let stdout_logger = Lwt_log.channel ~close_mode:`Keep ~channel:Lwt_io.stdout ()
let stderr_logger = Lwt_log.channel ~close_mode:`Keep ~channel:Lwt_io.stderr ()
let stdout ?(section=default_section) level str = Lwt_log.log ~section ~logger:stdout_logger ~level str
let stderr ?(section=default_section) level str = Lwt_log.log ~section ~logger:stdout_logger ~level str

let json_of_sexp sexp =
  let is_assoc sexp =
    match sexp with
    | Sexp.List [(Sexp.Atom _); _] -> true
    | _ -> false
  in
  let rec traverse sexp =
    match sexp with
    | Sexp.List ll when List.for_all ll ~f:is_assoc ->
      `Assoc (List.map ll ~f:(function
          | Sexp.List [Sexp.Atom head; tail] -> (head, (traverse tail))
          | _ -> failwith "Unreachable"
        ))
    | Sexp.List ll -> `List (List.map ~f:traverse ll)
    | Sexp.Atom x ->
      try
        let f = Float.of_string x in
        let i = Float.to_int f in
        if (Int.to_float i) = f then `Int i else `Float f
      with _ -> `String x
  in
  traverse sexp

let str_of_sexp ?(pretty=true) sexp =
  if pretty then Yojson.Basic.pretty_to_string (json_of_sexp sexp)
  else Yojson.Basic.to_string (json_of_sexp sexp)

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
  val section : string
end

module Make (Settings: Settings) : S = struct
  let section = Lwt_log.Section.make Settings.section
  let path_logger = lazy (Lwt_log.file ~mode:`Append ~perm:Fs.default_perm ~file_name:Settings.path ())
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
end
