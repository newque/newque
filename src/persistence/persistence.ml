open Core.Std
open Sexplib.Conv

module type Argument = sig
  type t [@@deriving sexp]
  type config

  val settings : config
  val create : config -> t Lwt.t

  val push_single : t -> chan_name:string -> Message.t -> Ack.t -> int Lwt.t
  val push_atomic : t -> chan_name:string -> Message.t list -> Ack.t -> int Lwt.t

  val size : t -> int Lwt.t
end

module type S = sig
  type config
  type t [@@deriving sexp]

  val push_single : chan_name:string -> Message.t -> Ack.t -> int Lwt.t
  val push_atomic : chan_name:string -> Message.t list -> Ack.t -> int Lwt.t

  val size : unit -> int Lwt.t
end

module Make (Argument: Argument) : S = struct
  type config = Argument.config
  type t = Argument.t

  let sexp_of_t = Argument.sexp_of_t
  let t_of_sexp = Argument.t_of_sexp

  let instance = Argument.create Argument.settings

  let push_single ~chan_name msg ack =
    let%lwt instance = instance in
    Argument.push_single instance ~chan_name msg ack

  let push_atomic ~chan_name msgs ack =
    let%lwt instance = instance in
    Argument.push_atomic instance ~chan_name msgs ack

  let size () =
    let%lwt instance = instance in
    Argument.size instance

end
