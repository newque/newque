open Core.Std
open Lwt

type 'a t = {
  table: 'a Lwt.u String.Table.t sexp_opaque;
  expiration: float; (* in seconds *)
} [@@deriving sexp]

let create expiration =
  let table = String.Table.create () in
  { table; expiration; }

let submit connector uid =
  let thread, wakener = wait () in
  String.Table.add_exn connector.table ~key:uid ~data:wakener;
  fun () ->
    try%lwt
      pick [thread; Lwt_unix.timeout connector.expiration]
    with
    | Lwt_unix.Timeout ->
      String.Table.remove connector.table uid;
      fail_with (sprintf "No response from upstream within %f seconds" connector.expiration)

let resolve connector uid obj =
  match String.Table.find_and_remove connector.table uid with
  | None ->
    print_endline (sprintf "Unknown UID received: %s" uid);
    fail_with (sprintf "Unknown UID received: %s" uid)
  | Some wakener ->
    wakeup_later wakener obj;
    return_unit
