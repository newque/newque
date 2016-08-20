open Core.Std

val outlog : string
val errlog : string

val stdout : Lwt_log_core.level -> string -> unit Lwt.t
val stderr : Lwt_log_core.level -> string -> unit Lwt.t

val pretty_sexp : Sexp.t -> string

module type S =
sig
  val debug : string -> unit Lwt.t
  val info : string -> unit Lwt.t
  val notice : string -> unit Lwt.t
  val warning : string -> unit Lwt.t
  val error : string -> unit Lwt.t
  val fatal : string -> unit Lwt.t
end

module type Settings = sig val path : string end

module Make : functor (Settings : Settings) -> S
