open Core

val log_level_of_variant : Config_t.config_log_level -> Lwt_log.level
val int_of_level : Lwt_log.level -> int

val lazy_level : int ref

val init : unit -> unit

val write_stdout : ?section:Lwt_log.section -> Lwt_log.level -> string -> unit Lwt.t
val write_stderr : ?section:Lwt_log.section -> Lwt_log.level -> string -> unit Lwt.t

type simple_logging = string -> unit Lwt.t
type lazy_logging = string Lazy.t -> unit Lwt.t

module type S =
sig
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

module Make : functor (Argument : Argument) -> S
