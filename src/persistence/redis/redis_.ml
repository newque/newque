open Core
open Lwt
open Redis_lwt

module Logger = Log.Make (struct let section = "Redis" end)

type redis_t = {
  pool: Redis_lwt.Client.connection Lwt_pool.t;
  host: string;
  port: int;
  auth: string option;
  database: int;
  keys: string list;
}

let create ~chan_name host port ~auth ~database ~pool_size =
  let pool = Redis_shared.get_conn_pool host port ~auth ~database ~pool_size ~info:Logger.info in
  let instance = {
    pool;
    host;
    port;
    auth;
    database;
    keys = ["index_id_"; "index_ts_"; "data_"; "meta_"]
           |> List.map ~f:(fun x -> sprintf "%s%s" x chan_name)
    ;
  }
  in
  return instance

module M = struct

  type t = redis_t

  let close instance = return_unit

  let push instance ~msgs ~ids =
    Lwt_pool.use instance.pool (fun conn ->
      let queue_args = Queue.create ~capacity:((Collection.length msgs) + (Collection.length ids) + 1) () in
      Queue.enqueue queue_args (Util.time_ns_string ());
      Collection.add_to_queue msgs queue_args;
      Collection.add_to_queue ids queue_args;
      let args = Queue.to_list queue_args in
      let%lwt reply = Redis_shared.exec_script conn "push" ~keys:instance.keys ~args ~debug:Logger.debug_lazy in
      match reply with
      | `Int saved -> return saved
      | `Int64 saved -> return (Int64.to_int_exn saved)
      | incorrect -> fail_with (sprintf "Invalid Redis Push result: %s" (Redis_shared.debug_reply incorrect))
    )

  let pull instance ~search ~fetch_last =
    Lwt_pool.use instance.pool (fun conn ->
      let (filter_type, filter_value) = Search.after_to_strings search in
      let args = [
        Int64.to_string search.Search.limit;
        filter_type;
        filter_value;
        Bool.to_string search.Search.only_once;
        Bool.to_string fetch_last;
      ]
      in
      let%lwt reply = Redis_shared.exec_script conn "pull" ~keys:instance.keys ~args ~debug:Logger.debug_lazy in
      match reply with
      | `Multibulk [
          `Multibulk r_msgs;
          `Bulk (Some r_last_rowid);
          `Bulk (Some r_last_id);
          `Bulk (Some r_last_timens);
          (`Multibulk _) as debug;
        ] ->
        async (fun () -> Logger.debug_lazy (lazy (sprintf "REDIS PULL DEBUG: %s" (Redis_shared.debug_reply debug))));
        let msgs = List.map r_msgs ~f:(fun bulk ->
            match bulk with
            | `Bulk (Some msg) -> msg
            | _ -> failwith "Redis Backend didn't return messages as strings"
          )
        in
        let last_rowid = Option.try_with (fun () -> Int64.of_string r_last_rowid) in
        let last_timens = Option.try_with (fun () -> Int64.of_string r_last_timens) in
        let meta = match fetch_last, last_timens with
          | true, (Some timens) -> Some (r_last_id, timens)
          | _ -> None
        in
        return (Collection.of_list msgs, last_rowid, meta)
      | incorrect ->
        fail_with (sprintf "Invalid Redis Pull result: %s" (Redis_shared.debug_reply incorrect))
    )

  let size instance =
    Lwt_pool.use instance.pool (fun conn ->
      let%lwt reply = Redis_shared.exec_script conn "size" ~keys:instance.keys ~args:[] ~debug:Logger.debug_lazy in
      match reply with
      | `Int i -> return (Int64.of_int i)
      | `Int64 i -> return i
      | incorrect ->
        fail_with (sprintf "Invalid Redis Size result: %s" (Redis_shared.debug_reply incorrect))
    )

  let delete instance = fail_with "Invalid operation: Redis delete"

  let health instance = Lwt_pool.use instance.pool (fun conn ->
      let%lwt reply = Redis_shared.exec_script conn "health" ~keys:instance.keys ~args:[] ~debug:Logger.debug_lazy in
      match reply with
      | `Bulk (Some "OK") -> return []
      | `Multibulk [
          `Int data_size;
          `Int index_id_size;
          `Int index_ts_size;
          `Int meta_size;
        ] ->
        return [
          sprintf "Data corruption detected [%d, %d, %d, %d]"
            data_size index_id_size index_ts_size meta_size
        ]
      | `Multibulk [
          `Int64 data_size;
          `Int64 index_id_size;
          `Int64 index_ts_size;
          `Int64 meta_size;
        ] ->
        return [
          sprintf "Data corruption detected [%Ld, %Ld, %Ld, %Ld]"
            data_size index_id_size index_ts_size meta_size
        ]
      | incorrect ->
        fail_with (sprintf "Invalid Redis Health result: %s" (Redis_shared.debug_reply incorrect))
    )

  let delete instance = Lwt_pool.use instance.pool (fun conn ->
      let%lwt reply = Redis_shared.exec_script conn "delete" ~keys:instance.keys ~args:[] ~debug:Logger.debug_lazy in
      match reply with
      | `Bulk (Some "OK") -> return_unit
      | incorrect ->
        fail_with (sprintf "Invalid Redis Delete result: %s" (Redis_shared.debug_reply incorrect))
    )

end
