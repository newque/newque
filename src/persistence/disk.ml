open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Disk" end)

type disk_t = {
  db: Sqlite.t;
  file: string;
  chan_name: string;
} [@@deriving sexp]

let create dir ~chan_name ~avg_read =
  let file = Printf.sprintf "%s%s.data" dir chan_name in
  let%lwt () = Logger.info (Printf.sprintf "Initializing %s" file) in
  let%lwt db = try%lwt
      Sqlite.create file ~avg_read
    with
    | ex ->
      (* TODO: Restart DB *)
      let%lwt () = Logger.error (Printf.sprintf "Failed to create DB %s with error %s. The %s channel will not work." file (Exn.to_string ex) chan_name) in
      fail ex
  in
  return {db; file; chan_name}

module M = struct

  type t = disk_t [@@deriving sexp]

  let close instance = return_unit

  let push instance ~msgs ~ids ack =
    try%lwt
      Sqlite.push instance.db msgs ids
    with
    | ex ->
      (* TODO: Restart DB *)
      let%lwt () = Logger.error (Printf.sprintf "Failed to write to %s with error %s. The DB must be restarted." instance.file (Exn.to_string ex)) in
      fail ex

  let pull instance ~mode =
    try%lwt
      Sqlite.pull instance.db ~mode
    with
    | ex ->
      (* TODO: Restart DB *)
      let%lwt () = Logger.error (Printf.sprintf "Failed to fetch from %s with error %s. The DB must be restarted." instance.file (Exn.to_string ex)) in
      fail ex

  let size instance =
    try%lwt
      Sqlite.size instance.db
    with
    | ex ->
      (* TODO: Restart DB *)
      let%lwt () = Logger.error (Printf.sprintf "Failed to count %s with error %s. The DB must be restarted." instance.file (Exn.to_string ex)) in
      fail ex

end
