open Core.Std
open Lwt
open Sexplib.Conv

module M = Persistence.Make (struct

    type config = unit
    type t = unit [@@deriving sexp]

    let settings : config = ()

    let create (pers : config) = return_unit

    let push_single (pers : t) ~chan_name (msg : Message.t) (ack : Ack.t) =
      return 1

    let push_atomic (pers : t) ~chan_name (msgs : Message.t list) (ack : Ack.t) =
      return 5

    let size (pers : t) =
      return 20

  end)
