open Core.Std
open Lwt

module type Template = sig
  type t [@@deriving sexp]

  val close : t -> unit Lwt.t

  val push : t -> msgs:string array -> ids:string array -> Ack.t -> int Lwt.t

  val pull_sync : t -> mode:Mode.Read.t -> string array Lwt.t

  val pull_stream : t -> mode:Mode.Read.t -> string Lwt_stream.t Lwt.t

  val size : t -> int64 Lwt.t
end

module type Argument = sig
  module IO : Template
  val create : unit -> IO.t Lwt.t
end

module type S = sig
  type t [@@deriving sexp]

  val push : Message.t array -> Id.t array -> Ack.t -> int Lwt.t

  val pull_sync : mode:Mode.Read.t -> string array Lwt.t

  val pull_stream : mode:Mode.Read.t -> string Lwt_stream.t Lwt.t

  val size : unit -> int64 Lwt.t
end

module Make (Argument: Argument) : S = struct
  type t = Argument.IO.t

  let sexp_of_t = Argument.IO.sexp_of_t
  let t_of_sexp = Argument.IO.t_of_sexp

  let instance = Argument.create ()

  let push msgs ids ack =
    let%lwt instance = instance in
    let ids = Array.map ~f:Id.to_string ids in
    let msgs = Array.map ~f:Message.serialize msgs in
    Argument.IO.push instance ~msgs ~ids ack

  let pull_sync ~mode =
    let%lwt instance = instance in
    let%lwt raw = Argument.IO.pull_sync instance ~mode in
    wrap (fun () -> Array.concat_map raw ~f:(fun x -> Message.contents (Message.parse_exn x)))

  let pull_stream ~mode =
    let%lwt instance = instance in
    Argument.IO.pull_stream instance ~mode

  let size () =
    let%lwt instance = instance in
    Argument.IO.size instance

end
