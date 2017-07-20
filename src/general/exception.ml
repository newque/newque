open Core
open Lwt

type exn_filter = (exn -> string list)

exception Multiple_public_exn of string list
exception Public_exn of string
exception Upstream_error of string

let json_error_regexp = Str.regexp "[ \\\n]"

(* Handles all kinds of errors, returns a human-readable string *)
let human ex =
  match ex with
  | Failure str -> str

  | Scripting.Lua_exn (str, _) -> str
  | Scripting.Lua_user_exn str -> str

  | Public_exn str -> str
  | Multiple_public_exn [] -> "Multiple Unknown Errors"
  | Multiple_public_exn [str] -> str
  | Multiple_public_exn errors ->
    sprintf "Multiple Errors: %s" (String.concat ~sep:", " errors)

  | Upstream_error str -> str

  | Protobuf.Decoder.Failure err ->
    sprintf "Protobuf Decoder Error: %s" (Protobuf.Decoder.error_to_string err)

  | Ag_oj_run.Error str
  | Yojson.Json_error str ->
    sprintf "JSON Parsing Error: %s" (Str.global_replace json_error_regexp " " str)

  | Unix.Unix_error (c, n, p) ->
    sprintf "System Error %s {call: %s(%s)}" (String.uppercase (Unix.Error.message c)) n p

  | unknown ->
    Exn.to_string unknown

let human_list ex = match ex with
  | Multiple_public_exn ll -> ll
  | ex -> [human ex]

let human_bt ex = (human ex), (Exn.backtrace ())

let full ex = sprintf "%s\n%s" (human ex) (Exn.backtrace ())

let default_error = "An error occured, please consult the logs for details."

(* All other error types are not considered public-facing *)
let is_public ex = match ex with
  | Scripting.Lua_user_exn _
  | Public_exn _
  | Multiple_public_exn _
  | Ag_oj_run.Error _
  | Yojson.Json_error _
  | Upstream_error _
  | Protobuf.Decoder.Failure _ -> true
  | _ -> false

(******************
   ENVIRONMENTS
 ******************)

let create_exception_filter ~section ~main_env ~listener_env =
  let module Logger = Log.Make (struct let section = section end) in
  match Option.value listener_env ~default:main_env with
  | Environment.Production -> begin
      fun ex ->
        match is_public ex with
        | true ->
          async (fun () -> Logger.notice (human ex));
          human_list ex
        | false ->
          async (fun () -> Logger.error (full ex));
          [default_error]
    end
  | Environment.Development -> begin
      fun ex ->
        let () = match is_public ex with
          | true ->
            async (fun () -> Logger.notice (human ex))
          | false ->
            async (fun () -> Logger.error (full ex))
        in
        human_list ex
    end
