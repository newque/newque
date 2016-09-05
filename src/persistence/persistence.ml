open Core.Std
open Sexplib.Conv

module type Template = sig
  type t [@@deriving sexp]

  val close : t -> unit Lwt.t

  val push : t -> chan_name:string -> Message.t -> Ack.t -> int Lwt.t

  val size : t -> int Lwt.t
end

module type Argument = sig
  module IO : Template
  val create : unit -> IO.t Lwt.t
end

module type S = sig
  type t [@@deriving sexp]

  val push : chan_name:string -> Message.t -> Ack.t -> int Lwt.t

  val size : unit -> int Lwt.t
end

module Make (Argument: Argument) : S = struct
  type t = Argument.IO.t

  let sexp_of_t = Argument.IO.sexp_of_t
  let t_of_sexp = Argument.IO.t_of_sexp

  let instance = Argument.create ()

  let push ~chan_name msg ack =
    let%lwt instance = instance in
    Argument.IO.push instance ~chan_name msg ack

  let size () =
    let%lwt instance = instance in
    Argument.IO.size instance

end
