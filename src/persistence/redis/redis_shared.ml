open Core
open Lwt
open Redis_lwt

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
# 26

let rec debug_reply ?(nested=false) reply =
  match reply with
  | `Bulk s -> sprintf "\"%s\"" (Option.value ~default:"---" s)
  | `Error s -> sprintf "(ERROR %s)" s
  | `Int i -> sprintf "%d" i
  | `Int64 i -> sprintf "(INT64 %Ld)" i
  | `Status s -> sprintf "(STATUS %s)" s
  | `Ask _ -> "ASK REDIRECTION"
  | `Moved _ -> "MOVED REDIRECTION"
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
let get_conn_pool host port ~auth ~database ~pool_size ~info =
  let key = sprintf "%s:%d:%d" host port database in
  String.Table.find_or_add pool_table key ~default:(fun () ->
    Lwt_pool.create pool_size
      ~check:(fun conn cb ->
        (* Runs after a call failed *)
        async (fun () -> Client.disconnect conn);
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
         let%lwt () = info (sprintf "Connecting to [%s]" key) in
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

let exec_script conn script ~keys ~args ~debug =
  async (fun () -> debug (lazy (debug_query script keys args)));
  match String.Table.find scripts script with
  | None -> fail_with (sprintf "Redis script %s could not be found" script)
  | Some sha -> Client.evalsha conn sha keys args
