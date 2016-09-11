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
      let%lwt () = Logger.error (Exn.to_string ex) in
      fail ex
  in
  let instance = {db; file; tablename;} in
  return instance

module M = struct

  type t = disk_t [@@deriving sexp]

  let close (pers : t) = return_unit

  let push (pers : t) ~chan_name ~msgs ~ids ack =
    let%lwt () = Logger.debug (List.sexp_of_t String.sexp_of_t msgs |> Util.string_of_sexp) in
    Sqlite.insert pers.db msgs ids

  let size (pers : t) =
    return 21

end
