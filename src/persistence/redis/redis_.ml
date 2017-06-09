open Core
open Lwt
open Redis_lwt

type redis_t = {
  pool: Redis_lwt.Client.connection Lwt_pool.t;
  host: string;
  port: int;
  auth: string option;
  database: int;
  keys: string list;
}

let rec debug_reply ?(nested=false) reply =
  match reply with
  | `Bulk s -> sprintf "[REDIS BULK] %s" (Option.value ~default:"---" s)
  | `Error s -> sprintf "[REDIS ERROR] %s" s
  | `Int i -> sprintf "[REDIS INT] %d" i
  | `Int64 i -> sprintf "[REDIS INT64] %s" (Int64.to_string i)
  | `Status s -> sprintf "[REDIS STATUS] %s" s
  | `Multibulk ll ->
    let stringified =
      List.map ll ~f:(debug_reply ~nested:true)
      |> String.concat ~sep:", "
    in
    if nested then sprintf "[%s]" stringified
    else sprintf "[REDIS MULTIBULK] [%s]" stringified

let lua_push = [%pla{|
#include "push.lua"
|}] |> Pla.print

let lua_pull = [%pla{|
#include "pull.lua"
|}] |> Pla.print

let scripts = String.Table.create ()
let exec_script conn script keys args =
  match String.Table.find scripts script with
  | None -> fail_with (sprintf "Redis script %s could not be found" script)
  | Some sha -> Client.evalsha conn sha keys args

let pool_table = String.Table.create ()
let get_conn_pool host port ~auth ~database ~pool_size =
  let key = sprintf "%s:%d:%d" host port database in
  String.Table.find_or_add pool_table key ~default:(fun () ->
    Lwt_pool.create pool_size (fun () ->
      let%lwt conn = Client.(connect {host; port}) in
      let%lwt () = match auth with
        | None -> return_unit
        | Some pw -> Client.auth conn pw
      in
      let%lwt () = if database <> 0 then Client.select conn database else return_unit in
      return conn
    )
  )

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

  let push instance ~msgs ~ids = fail_with "Invalid operation: Redis write"

  let pull instance ~search ~fetch_last = fail_with "Invalid operation: Redis read"

  let size instance = fail_with "Invalid operation: Redis count"

  let delete instance = fail_with "Invalid operation: Redis delete"

  let health instance = fail_with "Invalid operation: Redis health"

end
