open Core.Std
open Lwt

exception Upstream_error of string

type 'a t = {
  table: 'a Lwt.u String.Table.t sexp_opaque;
  expiration: float; (* in seconds *)
} [@@deriving sexp]

let create expiration =
  let table = String.Table.create () in
  { table; expiration; }

let submit connector uid outbound =
  let thread, wakener = wait () in
  String.Table.add_exn connector.table ~key:uid ~data:wakener;
  fun () ->
    try%lwt
      pick [thread; Lwt_unix.timeout connector.expiration]
    with ex ->
      String.Table.remove connector.table uid;
      match ex with
      | Lwt_unix.Timeout ->
        let error = Upstream_error (
            sprintf "No response from upstream [ZMQ %s] within %F seconds"
            outbound connector.expiration
          )
        in
        fail error

let resolve connector uid obj =
  match String.Table.find_and_remove connector.table uid with
  | None ->
    let error = Upstream_error (sprintf "Unknown UID received: %s" uid) in
    fail error
  | Some wakener ->
    wakeup_later wakener obj;
    return_unit
