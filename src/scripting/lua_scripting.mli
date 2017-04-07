open Core.Std
open Lua_api

type t

exception Lua_exn of string * Lua.thread_status

type _ lua_type =
  | Lua_integer : int lua_type
  | Lua_string : string Option.t lua_type
  | Lua_integer_table : int Collection.t lua_type
  | Lua_string_table : string Collection.t lua_type
  | Lua_string_table_pair : (string Collection.t * string Collection.t) lua_type

val create : mappers:string array -> t Lwt.t

val run_mappers :
  t ->
  string array ->
  msgs:string Collection.t ->
  ids:string Collection.t ->
  (string Collection.t * string Collection.t) Lwt.t
