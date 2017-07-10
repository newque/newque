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

let lua_push = [%pla{|
 #include "push.lua"
 |}] |> Pla.print

let lua_pull = [%pla{|
 #include "delete_rowids.lua"
 #include "pull.lua"
 |}] |> Pla.print

let lua_size = [%pla{|
 #include "size.lua"
 |}] |> Pla.print

let lua_health = [%pla{|
 #include "health.lua"
 |}] |> Pla.print

let lua_delete = [%pla{|
  #include "delete.lua"
  |}] |> Pla.print
# 37

let rec debug_reply ?(nested=false) reply =
  match reply with
  | `Bulk s -> sprintf "\"%s\"" (Option.value ~default:"---" s)
  | `Error s -> sprintf "(ERROR %s)" s
  | `Int i -> sprintf "%d" i
  | `Int64 i -> sprintf "(INT64 %Ld)" i
  | `Status s -> sprintf "(STATUS %s)" s
  | `Multibulk ll ->
    let stringified =
      List.map ll ~f:(debug_reply ~nested:true)
      |> String.concat ~sep:", "
    in
    if nested then sprintf "{%s}" stringified
    else sprintf "{%s}" stringified

let scripts = String.Table.create ()

let debug_query script keys args =
  sprintf "evalsha %s %d %s (%d arguments)"
    (String.Table.find_exn scripts script)
    (List.length keys)
    (String.concat ~sep:" " keys)
    (List.length args)

let load_scripts conn =
  let load_script name lua =
    let%lwt sha = Client.script_load conn lua in
    String.Table.add scripts ~key:name ~data:sha |> ignore;
    return_unit
  in
  join [
    (load_script "push" lua_push);
    (load_script "pull" lua_pull);
    (load_script "size" lua_size);
    (load_script "health" lua_health);
    (load_script "delete" lua_delete);
  ]

let last_used_table = String.Table.create ()
let pool_table = String.Table.create ()
let get_conn_pool host port ~auth ~database ~pool_size =
  let key = sprintf "%s:%d:%d" host port database in
  String.Table.find_or_add pool_table key ~default:(fun () ->
    Lwt_pool.create pool_size
      ~check:(fun conn cb ->
        (* Runs after a call failed *)
        ignore (async (fun () -> Client.disconnect conn));
        cb false
      )
      ~validate:(fun conn ->
        (* Runs before a connection is used *)
        let now = Util.time_ns_int63 () in
        let last_used = Option.value ~default:Int63.zero (String.Table.find last_used_table key) in
        String.Table.set last_used_table ~key ~data:now;
        if Int63.(now < (last_used + (of_int 2_000_000_000)))
        then return true
        else try%lwt
            Client.ping conn
          with err ->
            fail_with "Server unreachable"
      )
      (fun () ->
         let%lwt () = Logger.info (sprintf "Connecting to [%s]" key) in
         let%lwt conn = Client.(connect {host; port}) in
         let%lwt () = match auth with
           | None -> return_unit
           | Some pw -> Client.auth conn pw
         in
         let%lwt () = if database <> 0 then Client.select conn database else return_unit in
         let%lwt () = load_scripts conn in
         return conn
      )
  )

let exec_script conn script keys args =
  async (fun () -> Logger.debug_lazy (lazy (debug_query script keys args)));
  match String.Table.find scripts script with
  | None -> fail_with (sprintf "Redis script %s could not be found" script)
  | Some sha -> Client.evalsha conn sha keys args

let create ~chan_name host port ~auth ~database ~pool_size =
  let pool = get_conn_pool host port ~auth ~database ~pool_size in
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
      let%lwt reply = exec_script conn "push" instance.keys args in
      match reply with
      | `Int saved -> return saved
      | `Int64 saved -> return (Int64.to_int_exn saved)
      | incorrect -> fail_with (sprintf "Invalid Redis Push result: %s" (debug_reply incorrect))
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
      let%lwt reply = exec_script conn "pull" instance.keys args in
      match reply with
      | `Multibulk [
          `Multibulk r_msgs;
          `Bulk (Some r_last_rowid);
          `Bulk (Some r_last_id);
          `Bulk (Some r_last_timens);
          (`Multibulk _) as debug;
        ] ->
        async (fun () -> Logger.debug_lazy (lazy (sprintf "REDIS PULL DEBUG: %s" (debug_reply debug))));
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
        fail_with (sprintf "Invalid Redis Pull result: %s" (debug_reply incorrect))
    )

  let size instance =
    Lwt_pool.use instance.pool (fun conn ->
      let%lwt reply = exec_script conn "size" instance.keys [] in
      match reply with
      | `Int i -> return (Int64.of_int i)
      | `Int64 i -> return i
      | incorrect ->
        fail_with (sprintf "Invalid Redis Size result: %s" (debug_reply incorrect))
    )

  let delete instance = fail_with "Invalid operation: Redis delete"

  let health instance = Lwt_pool.use instance.pool (fun conn ->
      let%lwt reply = exec_script conn "health" instance.keys [] in
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
        fail_with (sprintf "Invalid Redis Health result: %s" (debug_reply incorrect))
    )

  let delete instance = Lwt_pool.use instance.pool (fun conn ->
      let%lwt reply = exec_script conn "delete" instance.keys [] in
      match reply with
      | `Bulk (Some "OK") -> return_unit
      | incorrect ->
        fail_with (sprintf "Invalid Redis Delete result: %s" (debug_reply incorrect))
    )

end
