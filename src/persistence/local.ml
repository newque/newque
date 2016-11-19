open Core.Std
open Lwt

module Logger = Log.Make (struct let path = Log.outlog let section = "Local" end)

type local_t = {
  mutable db: Sqlite.t;
  avg_read: int;
  file: string;
  chan_name: string;
  mutex: Lwt_mutex.t sexp_opaque;
} [@@deriving sexp]

let create ~file ~chan_name ~avg_read =
  let mutex = Lwt_mutex.create () in
  let%lwt () = Logger.info (Printf.sprintf "Initializing %s (%s)" file chan_name) in
  let%lwt db = try%lwt
      Sqlite.create file ~avg_read
    with
    | ex ->
      let%lwt () = Logger.error (Printf.sprintf "Failed to create DB %s with error %s. The channel %s will not work." file (Exn.to_string ex) chan_name) in
      fail ex
  in
  return {db; avg_read; file; chan_name; mutex}

module M = struct

  type t = local_t [@@deriving sexp]

  let close_nolock instance =
    try%lwt
      Sqlite.close instance.db
    with
    | ex ->
      let%lwt () = Logger.error (Printf.sprintf "Failed to close %s (%s) with error %s." instance.file instance.chan_name (Exn.to_string ex)) in
      fail ex

  let close instance = Lwt_mutex.with_lock instance.mutex (fun () -> close_nolock instance)

  let restart_nolock instance =
    let%lwt () = try%lwt
        close_nolock instance
      with
      | ex ->
        Logger.error (Printf.sprintf "Failed to restart %s (%s) with error %s." instance.file instance.chan_name (Exn.to_string ex))
    in
    create ~file:instance.file ~chan_name:instance.chan_name ~avg_read:instance.avg_read

  let handle_failure instance ex ~errstr =
    let%lwt () = Logger.error errstr in
    let%lwt restarted = restart_nolock instance in
    instance.db <- restarted.db;
    fail ex

  let push instance ~msgs ~ids =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.push instance.db msgs ids
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to write to %s (%s) with error %s. Restarting." instance.file instance.chan_name (Exn.to_string ex))
    )

  let pull instance ~search ~fetch_last =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.pull instance.db ~search ~fetch_last
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to query from %s (%s) with error %s." instance.file instance.chan_name (Exn.to_string ex))
    )

  let size instance =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.size instance.db
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to count %s (%s) with error %s." instance.file instance.chan_name (Exn.to_string ex))
    )

end
