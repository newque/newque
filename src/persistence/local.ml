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
let read_batch_size = 2
  #else
let read_batch_size = 500
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

  let push instance ~msgs ~ids ack =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.push instance.db msgs ids
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to write to %s (%s) with error %s. Restarting." instance.file instance.chan_name (Exn.to_string ex))
    )

  let pull_data instance ~search =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.pull instance.db ~search
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to query from %s (%s) with error %s." instance.file instance.chan_name (Exn.to_string ex))
    )

  let single instance ~rowid =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.single instance.db ~rowid
      with
      | ex ->
        handle_failure instance ex ~errstr:(Printf.sprintf "Failed to fetch single from %s (%s) with error %s." instance.file instance.chan_name (Exn.to_string ex))
    )

  let pull_slice instance ~search =
    let%lwt (payloads, last_rowid) = pull_data instance ~search in
    let open Persistence in
    match last_rowid with
    | None ->
      return { metadata = None; payloads }
    | Some last_internal_id ->
      let%lwt (last_id, last_timens) = single instance ~rowid:last_internal_id in
      return { metadata = (Some {last_internal_id; last_id; last_timens}); payloads }

  let pull_stream instance ~search =
    let open Persistence in
    (* Ugly imperative code for performance here *)
    let left = ref search.limit in
    let next_search = ref {search with limit = Int64.min !left (Int.to_int64 read_batch_size)} in
    wrap (fun () ->
      Lwt_stream.from (fun () ->
        if !next_search.limit <= Int64.zero then return_none else
        let%lwt (payloads, last_rowid) = pull_data instance ~search:!next_search in
        match last_rowid with
        | None -> return_none
        | Some rowid ->
          if Array.is_empty payloads then return_none else
          let payloads_count = Int.to_int64 (Array.length payloads) in
          left := Int64.(-) !left payloads_count;
          let () = next_search := {
              limit = Int64.min !left (Int.to_int64 read_batch_size);
              filters = Array.append [|`After_rowid rowid|] search.filters;
            } in
          return (Some payloads)
      )
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
