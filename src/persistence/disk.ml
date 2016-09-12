open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Disk" end)

type disk_t = {
  db: Sqlite.t;
  file: string;
  tablename: string;
} [@@deriving sexp]

let create dir tablename =
  let file = Printf.sprintf "%s%s.data" dir tablename in
  let%lwt () = Logger.info (Printf.sprintf "Initializing %s" file) in
  let%lwt db = try%lwt
      Sqlite.create file
    with
    | ex ->
      (* TODO: Restart DB *)
      let%lwt () = Logger.error (Printf.sprintf "Failed to create DB %s with error %s. The %s channel will not work." file (Exn.to_string ex) tablename) in
      fail ex
  in
  return {db; file; tablename}

module M = struct

  type t = disk_t [@@deriving sexp]

  let close instance = return_unit

  let push instance ~chan_name ~msgs ~ids ack =
    let%lwt () = Logger.debug (List.sexp_of_t String.sexp_of_t msgs |> Util.string_of_sexp) in
    try%lwt
      Sqlite.insert instance.db msgs ids
    with
    | ex ->
      (* TODO: Restart DB *)
      let%lwt () = Logger.error (Printf.sprintf "Failed to write to %s with error %s. The DB must be restarted." instance.file (Exn.to_string ex)) in
      return 0

  let size instance =
    return 21

end
