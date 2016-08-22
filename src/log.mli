open Core.Std

val outlog : string
val errlog : string

val stdout : ?section:Lwt_log.section -> Lwt_log.level -> string -> unit Lwt.t
val stderr : ?section:Lwt_log.section -> Lwt_log.level -> string -> unit Lwt.t

val json_of_sexp : Sexp.t -> Yojson.Basic.json
val str_of_sexp : ?pretty:bool -> Sexp.t -> string

module type S =
sig
  val debug : string -> unit Lwt.t
  val info : string -> unit Lwt.t
  val notice : string -> unit Lwt.t
  val warning : string -> unit Lwt.t
  val error : string -> unit Lwt.t
  val fatal : string -> unit Lwt.t
end

module type Settings =
sig
  val path : string
  val section : string
end

module Make : functor (Settings : Settings) -> S
