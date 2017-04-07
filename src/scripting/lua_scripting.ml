open Core.Std
open Lwt
open Lua_api

module Logger = Log.Make (struct let section = "Lua" end)

type t = {
  ls: Lua.state;
  mutex: Lwt_mutex.t;
}

exception Lua_exn of string * Lua.thread_status

let registry_mapper_key chan_name = sprintf "NEWQUE_%s_MAPPER" chan_name

let stack_size ls = Lua.gettop ls
let empty_stack ls = Lua.pop ls (stack_size ls)

let create_lua_state () =
  wrap (fun () ->
    let ls = LuaL.newstate ?max_memory_size:(None) () in
    LuaL.openlibs ls;
    (* Edit package.path *)
    Lua.getglobal ls "package";
    Lua.getfield ls (-1) "path";
    let path = match Lua.tostring ls (-1) with
      | None -> failwith "Cannot retrieve Lua package.path"
      | Some path -> path
    in
    let new_path = sprintf "%s;%s" "./conf/scripts/?.lua" path in
    Lua.pop ls 1;
    Lua.pushstring ls new_path;
    Lua.setfield ls (-2) "path";
    Lua.setglobal ls "package";
    ls
  )

let thread_status_to_string ts =
  match ts with
  | Lua.LUA_OK -> "LUA_OK"
  | Lua.LUA_YIELD -> "LUA_YIELD"
  | Lua.LUA_ERRRUN -> "LUA_ERRRUN"
  | Lua.LUA_ERRSYNTAX -> "LUA_ERRSYNTAX"
  | Lua.LUA_ERRMEM -> "LUA_ERRMEM"
  | Lua.LUA_ERRERR -> "LUA_ERRERR"
  | Lua.LUA_ERRFILE -> "LUA_ERRFILE"

let get_lua_exn ls ts =
  let err_msg = sprintf "%s %s"
      (thread_status_to_string ts)
      (Option.value ~default:"" (Lua.tostring ls (-1)))
  in
  empty_stack ls;
  Lua_exn (err_msg, ts)


external lua_parallel_pcall__wrapper : Lua.state -> int -> int -> int -> int = "lua_parallel_pcall__stub"
external lua_parallel_multi_pcall__wrapper : Lua.state -> int -> int -> int = "lua_parallel_multi_pcall__stub"

let parallel_pcall ls nargs nresults errfunc =
  lua_parallel_pcall__wrapper ls nargs nresults errfunc
  |> Lua.thread_status_of_int

let parallel_multi_pcall ls nargsresults nmappers =
  lua_parallel_multi_pcall__wrapper ls nargsresults nmappers
  |> Lua.thread_status_of_int


type _ lua_type =
  | Lua_integer : int lua_type
  | Lua_string : string Option.t lua_type
  | Lua_integer_table : int Collection.t lua_type
  | Lua_string_table : string Collection.t lua_type
  | Lua_string_table_pair : (string Collection.t * string Collection.t) lua_type

let extract_string_table ls =
  Array.init (Lua.objlen ls (-1)) ~f:(fun i ->
    Lua.rawgeti ls (-1) (i+1);
    let str_opt = Lua.tostring ls (-1) in
    Lua.pop ls 1;
    str_opt
  )
  |> Array.filter_opt
  |> Collection.of_array

let extract_lua_result_sync : type a. Lua.state -> a lua_type -> a =
  fun ls return_type ->
    let ret : a = match return_type with
      | Lua_integer -> Lua.tointeger ls (-1)
      | Lua_string -> Lua.tostring ls (-1)
      | Lua_integer_table ->
        Array.init (Lua.objlen ls (-1)) ~f:(fun i ->
          Lua.rawgeti ls (-1) (i+1);
          let int_v = Lua.tointeger ls (-1) in
          Lua.pop ls 1;
          int_v
        )
        |> Collection.of_array
      | Lua_string_table ->
        extract_string_table ls
      | Lua_string_table_pair ->
        (* Check lengths *)
        let first_len = Lua.objlen ls (-2) in
        let second_len = Lua.objlen ls (-1) in
        if first_len <> second_len then
          let () = Lua.pop ls 2 in
          failwith (sprintf
              "Scripts on this channel returned a mismatching number of IDs [%d] and Messages [%d]"
              second_len
              first_len
          )
        else
        let first = extract_string_table ls in
        Lua.pop ls 1;
        let second = extract_string_table ls in
        (first, second)
    in
    Lua.pop ls 1;
    ret

let push_coll_to_stack_sync ls arr =
  let len = Collection.length arr in
  Lua.createtable ls len 0;
  let pos = stack_size ls in
  Collection.iteri arr ~f:(fun i s ->
    Lua.pushstring ls s;
    Lua.rawseti ls pos (i + 1)
  )

let load_script ls script =
  let path = sprintf "%s%s" Fs.conf_scripts_dir script in
  let%lwt () = Logger.info (sprintf "Loading [%s]" path) in
  let%lwt contents = Lwt_io.chars_of_file path |> Lwt_stream.to_string in

  (* Compile *)
  let%lwt () = match LuaL.loadstring ls contents with
    | Lua.LUA_OK -> return_unit
    | lua_err -> fail (get_lua_exn ls lua_err)
  in

  (* Run *)
  let%lwt () = match Lua.pcall ls 0 1 0 with
    | Lua.LUA_OK -> return_unit
    | lua_err -> fail (get_lua_exn ls lua_err)
  in

  (* Validate function *)
  let () = if not (Lua.isfunction ls (-1)) then
      failwith (sprintf "Script [%s] didn't return a function" script)
  in

  (* Register function *)
  Lua.pushstring ls (registry_mapper_key script);
  Lua.insert ls (-2); (* Swap newly added string with the function underneath *)
  Lua.rawset ls Lua.registryindex;
  let%lwt () = Logger.info (sprintf "Loaded [%s]" path) in
  return_unit

let create ~mappers =
  let mutex = Lwt_mutex.create () in
  let%lwt () = Logger.info (sprintf "Initializing Lua VM with scripts [%s]." (String.concat_array ~sep:"," mappers)) in
  let%lwt ls = create_lua_state () in
  let%lwt () = Lwt_list.iter_s (fun script ->
      load_script ls script
    ) (Array.to_list mappers)
  in
  let instance = { ls; mutex; } in
  return instance

let run_lua_fn : type a. t -> string -> a lua_type -> (Lua.state -> int) -> a Lwt.t =
  fun {ls; mutex;} script_name return_type push_args ->
    Lwt_mutex.with_lock mutex (fun () ->
      Lwt_preemptive.detach (fun () ->
        Lua.getfield ls Lua.registryindex (registry_mapper_key script_name);
        let args_count = push_args ls in
        match parallel_pcall ls args_count 1 0 with
        | Lua.LUA_OK ->
          extract_lua_result_sync ls return_type
        | lua_err -> raise (get_lua_exn ls lua_err)
      ) ()
    )

let run_lua_fn_chain : type a. t -> string array -> a lua_type -> (Lua.state -> int) -> a Lwt.t =
  fun {ls; mutex;} script_names return_type push_args ->
    Lwt_mutex.with_lock mutex (fun () ->
      Lwt_preemptive.detach (fun () ->
        for i = (Array.length script_names) - 1 downto 0 do
          Lua.getfield ls Lua.registryindex (registry_mapper_key (Array.get script_names i))
        done;
        let args_count = push_args ls in
        match parallel_multi_pcall ls args_count (Array.length script_names) with
        | Lua.LUA_OK ->
          extract_lua_result_sync ls return_type
        | lua_err -> raise (get_lua_exn ls lua_err)
      ) ()
    )

let run_mappers instance mappers ~msgs ~ids =
  run_lua_fn_chain instance mappers Lua_string_table_pair (fun ls ->
    push_coll_to_stack_sync ls ids;
    push_coll_to_stack_sync ls msgs;
    2
  )
