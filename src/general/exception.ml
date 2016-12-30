open Core.Std

exception Multiple_exn of string list

let json_error_regexp = Str.regexp "[ \\\n]"

let human ex = match ex with
  | Failure str -> str

  | Multiple_exn [] -> "Multiple Unknown Errors"
  | Multiple_exn [str] -> str
  | Multiple_exn errors ->
    sprintf "Multiple Errors: %s" (String.concat ~sep:", " errors)

  | Connector.Upstream_error str -> str

  | Protobuf.Decoder.Failure err ->
    sprintf "Protobuf Decoder Error: %s" (Protobuf.Decoder.error_to_string err)

  | Ag_oj_run.Error str
  | Yojson.Json_error str ->
    sprintf "JSON Parsing Error: %s" (Str.global_replace json_error_regexp " " str)

  | Unix.Unix_error (c, n, p) ->
    sprintf "System Error %s {call: %s(%s)}" (String.uppercase (Unix.error_message c)) n p

  | unknown ->
    Exn.to_string unknown

let human_list ex = match ex with
  | Multiple_exn ll -> ll
  | ex -> [human ex]

let human_bt ex = (human ex), (Exn.backtrace ())

let full ex = sprintf "%s\n%s" (human ex) (Exn.backtrace ())
