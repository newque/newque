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

#ifdef DEBUG
let batch_size = 2
  #else
let batch_size = 100
  #endif

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
    try%lwt
      let%lwt () = close_nolock instance in
      let%lwt restarted = create ~file:instance.file ~chan_name:instance.chan_name ~avg_read:instance.avg_read in
      return (Ok restarted)
    with
    | ex ->
      return (Error (Printf.sprintf "Failed to restart %s (%s) with error %s." instance.file instance.chan_name (Exn.to_string ex)))

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
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to write to %s (%s) with error %s. Restarting." instance.file instance.chan_name (Exn.to_string ex))
    )

  let pull_slice instance max_read ~mode =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.pull instance.db max_read mode
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to fetch from %s (%s) with error %s." instance.file instance.chan_name (Exn.to_string ex))
    )

  let pull_stream instance max_read ~mode =
    let (stream, push) = Lwt_stream.create () in
    let rec run left =
      if left = 0 then return_unit else
      let took = min left batch_size in
      let%lwt payloads = pull_slice instance max_read ~mode in
      Array.iter payloads ~f:(fun x -> push (Some x));
      run (left - took)
    in
    async (fun () -> run max_read);
    return stream

  let size instance =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.size instance.db
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to count %s (%s) with error %s." instance.file instance.chan_name (Exn.to_string ex))
    )

end
