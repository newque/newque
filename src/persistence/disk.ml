open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Disk" end)

type disk_t = {
  mutable db: Sqlite.t;
  dir: string;
  chan_name: string;
  avg_read: int;
  file: string;
  mutex: Lwt_mutex.t sexp_opaque;
} [@@deriving sexp]

let create dir ~chan_name ~avg_read =
  let file = Printf.sprintf "%s%s.data" dir chan_name in
  let mutex = Lwt_mutex.create () in
  let%lwt () = Logger.info (Printf.sprintf "Initializing %s" file) in
  let%lwt db = try%lwt
      Sqlite.create file ~avg_read
    with
    | ex ->
      let%lwt () = Logger.error (Printf.sprintf "Failed to create DB %s with error %s. The channel %s will not work." file (Exn.to_string ex) chan_name) in
      fail ex
  in
  return {db; dir; chan_name; avg_read; file; mutex}

module M = struct

  type t = disk_t [@@deriving sexp]

  let close_nolock instance =
    try%lwt
      Sqlite.close instance.db
    with
    | ex ->
      (* TODO: Restart DB *)
      let%lwt () = Logger.error (Printf.sprintf "Failed to close %s with error %s." instance.file (Exn.to_string ex)) in
      fail ex

  let close instance = Lwt_mutex.with_lock instance.mutex (fun () -> close_nolock instance)

  let restart_nolock instance =
    try%lwt
      let%lwt () = close_nolock instance in
      let%lwt restarted = create instance.dir ~chan_name:instance.chan_name ~avg_read:instance.avg_read in
      return (Ok restarted)
    with
    | ex ->
      return (Error (Printf.sprintf "Failed to restart %s with error %s." instance.file (Exn.to_string ex)))

  let handle_failure instance ex ~errstr =
    let%lwt () = Logger.error errstr in
    let%lwt () = match%lwt restart_nolock instance with
      | Ok restarted ->
        instance.db <- restarted.db;
        return_unit
      | Error str ->
        Logger.error str
    in
    fail ex

  let push instance ~msgs ~ids ack =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.push instance.db msgs ids
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to write to %s with error %s. Restarting." instance.file (Exn.to_string ex))
    )

  let pull instance ~mode =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.pull instance.db ~mode
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to fetch from %s with error %s." instance.file (Exn.to_string ex))
    )

  let size instance =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.size instance.db
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to count %s with error %s." instance.file (Exn.to_string ex))
    )

end
