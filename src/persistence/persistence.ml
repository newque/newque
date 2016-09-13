open Core.Std

module type Template = sig
  type t [@@deriving sexp]

  val close : t -> unit Lwt.t

  val push : t -> msgs:string list -> ids:string list -> Ack.t -> int Lwt.t

  val size : t -> int Lwt.t
end

module type Argument = sig
  module IO : Template
  val create : unit -> IO.t Lwt.t
end

module type S = sig
  type t [@@deriving sexp]

  val push : Message.t list -> Id.t list -> Ack.t -> int Lwt.t

  val size : unit -> int Lwt.t
end

module Make (Argument: Argument) : S = struct
  type t = Argument.IO.t

  let sexp_of_t = Argument.IO.sexp_of_t
  let t_of_sexp = Argument.IO.t_of_sexp

  let instance = Argument.create ()

  let push msgs ids ack =
    let%lwt instance = instance in
    let ids = List.map ~f:Id.to_string ids in
    (* DEBUGGING: Currently writing JSON rather than Protobuf to make development easier *)
    (* let msgs = List.map ~f:Message.serialize msgs in *)
    let msgs = List.map ~f:(fun msg -> Message.sexp_of_t msg |> Util.string_of_sexp ~pretty:false) msgs in
    Argument.IO.push instance ~msgs ~ids ack

  let size () =
    let%lwt instance = instance in
    Argument.IO.size instance

end
