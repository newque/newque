open Core.Std
open Lwt

module Logger = Log.Make (struct let section = "Local" end)

type local_t = {
  mutable db: Sqlite.t;
  file: string;
  chan_name: string;
  avg_read: int;
  mutex: Lwt_mutex.t;
}

let create ~file ~chan_name ~avg_read =
  let mutex = Lwt_mutex.create () in
  let%lwt () = Logger.info (sprintf "[%s] Initializing %s." chan_name file) in
  let%lwt db = try%lwt
      Sqlite.create file ~avg_read
    with
    | ex ->
      let%lwt () = Logger.error (sprintf
            "[%s] Failed to create %s. %s" chan_name file (Exception.full ex)
        )
      in
      fail ex
  in
  let instance = {
    db;
    file;
    chan_name;
    avg_read;
    mutex;
  }
  in
  return instance

module M = struct

  type t = local_t

  let close_nolock instance =
    try%lwt
      Sqlite.close instance.db
    with
    | ex ->
      let%lwt () = Logger.error (sprintf
            "[%s] Failed to close %s. %s" instance.chan_name instance.file (Exception.full ex)
        )
      in
      fail ex

  let close instance = Lwt_mutex.with_lock instance.mutex (fun () -> close_nolock instance)

  let restart_nolock instance =
    let%lwt () = try%lwt
        close_nolock instance
      with
      | ex ->
        Logger.error (sprintf
            "[%s] Failed to restart %s. %s" instance.chan_name instance.file (Exception.full ex)
        )
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
        Sqlite.push instance.db ~msgs ~ids
      with
      | ex ->
        handle_failure instance ex ~errstr:(sprintf
            "[%s] Failed to write to %s. %s"
            instance.chan_name instance.file (Exception.full ex)
        )
    )

  let pull instance ~search ~fetch_last =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.pull instance.db ~search ~fetch_last
      with
      | ex ->
        handle_failure instance ex ~errstr:(sprintf
            "[%s] Failed to read from %s. %s"
            instance.chan_name instance.file (Exception.full ex)
        )
    )

  let size instance =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.size instance.db
      with
      | ex ->
        handle_failure instance ex ~errstr:(sprintf
            "[%s] Failed to count from %s. %s"
            instance.chan_name instance.file (Exception.full ex)
        )
    )

  let delete instance =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      let%lwt () = Logger.info (sprintf "Deleting data in [%s]" instance.chan_name) in
      try%lwt
        Sqlite.delete instance.db
      with
      | ex ->
        handle_failure instance ex ~errstr:(sprintf
            "[%s] Failed to delete from %s. %s"
            instance.chan_name instance.file (Exception.full ex)
        )
    )

  let health instance =
    Lwt_mutex.with_lock instance.mutex (fun () ->
      try%lwt
        Sqlite.health instance.db
      with
      | ex ->
        handle_failure instance ex ~errstr:(sprintf
            "[%s] Failed to check health of %s. %s"
            instance.chan_name instance.file (Exception.full ex)
        )
    )

end
