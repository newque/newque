open Core
open Lwt
open Lua_api

module Logger = Log.Make (struct let section = "Lua" end)

type t = {
  ls: Lua.state;
  mutex: Lwt_mutex.t;
}

exception Lua_exn of string * Lua.thread_status
exception Lua_user_exn of string

external lua_parallel_multi_pcall__wrapper : Lua.state -> int -> int -> int = "lua_parallel_multi_pcall"

let parallel_multi_pcall ls nargsresults nmappers =
  lua_parallel_multi_pcall__wrapper ls nargsresults nmappers
  |> Lua.thread_status_of_int

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

    (* Prepare a safe Lua exception catcher *)
    let _ = Lua.atpanic ls (fun ls ->
        let msg = Option.value ~default:"No message found on the stack" (Lua.tostring ls (-1)) in
        let str = sprintf "A Lua VM panic occured: [%s]" msg in
        async (fun () -> Logger.error str);
        (* This exception allows us to escape Lua's call to exit(0) *)
        failwith str
      )
    in
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

let raise_lua_exn ~during ls ts =
  let type_ = Lua.type_ ls (-1) in
  let ex = match type_ with
    | Lua.LUA_TSTRING | Lua.LUA_TNUMBER ->
      let err_str = Option.value ~default:"" (Lua.tostring ls (-1)) in
      let err_msg = sprintf "Unexpected error [%s] [%s] during %s"
          (thread_status_to_string ts) err_str during
      in
      Lua_exn (err_msg, ts)

    | Lua.LUA_TTABLE ->
      Lua.getfield ls (-1) "location";
      let location = Option.value ~default:"" (Lua.tostring ls (-1)) in
      Lua.getfield ls (-2) "message";
      let message = Option.value ~default:"" (Lua.tostring ls (-1)) in
      Lua_user_exn (sprintf "Error [%s] occured in [%s]" message location)

    | Lua.LUA_TNONE
    | Lua.LUA_TNIL
    | Lua.LUA_TBOOLEAN
    | Lua.LUA_TLIGHTUSERDATA
    | Lua.LUA_TFUNCTION
    | Lua.LUA_TUSERDATA
    | Lua.LUA_TTHREAD ->
      let err_msg = sprintf "Error [%s]: invalid value of type [%s] was thrown during %s"
          (thread_status_to_string ts) (Lua.typename ls type_) during
      in
      Lua_exn (err_msg, ts)
  in
  empty_stack ls;
  raise ex

type _ lua_type =
  | Lua_integer : int lua_type
  | Lua_string : string Option.t lua_type
  | Lua_integer_table : int Collection.t lua_type
  | Lua_string_table : string Collection.t lua_type
  | Lua_string_table_pair : (string Collection.t * string Collection.t) lua_type

(* Will eventually need to be rewritten in C *)
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
    | lua_err -> raise_lua_exn ls lua_err ~during:(sprintf "initial compilation of [%s]" path)
  in

  (* Run *)
  let%lwt () = match Lua.pcall ls 0 1 0 with
    | Lua.LUA_OK -> return_unit
    | lua_err -> raise_lua_exn ls lua_err ~during:(sprintf "initial execution of [%s]" path)
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
        | lua_err ->
          raise_lua_exn ls lua_err ~during:(sprintf "execution of [%s]" (String.concat_array ~sep:"," script_names))
      ) ()
    )

let run_mappers instance mappers ~msgs ~ids =
  let lua_result = run_lua_fn_chain instance mappers Lua_string_table_pair (fun ls ->
      push_coll_to_stack_sync ls ids;
      push_coll_to_stack_sync ls msgs;
      2
    )
  in
  (* If not a user error, print it into the logs *)
  try%lwt lua_result with
  | Lua_exn (err, _) ->
    let%lwt () = Logger.error err in
    fail (Lua_user_exn "Unexpected error during script execution")
