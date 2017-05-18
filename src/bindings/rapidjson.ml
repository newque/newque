open Core
open Lwt

module Logger = Log.Make (struct let section = "JSONSchema" end)

type t = {
  schema_name: string;
  parallelism_threshold: int;
}

external rj_register_schema : string -> string -> string option = "rj_register_schema"
external rj_schema_exists : string -> bool = "rj_schema_exists"
external rj_validate_json : string -> string -> string option = "rj_validate_json"
external rj_validate_multiple_json : string -> string array -> string option = "rj_validate_multiple_json"

let validate_single = fun name raw ->
  match rj_validate_json name raw with
  | None -> Result.ok_unit
  | Some err -> Error err

let validate_multiple = fun name raws ->
  match rj_validate_multiple_json name raws with
  | None -> Result.ok_unit
  | Some err -> Error err

(* Otherwise multiple channel can race to mutex_create the same schema at the same time *)
let mutex_create = Lwt_mutex.create ()

let meta_schema = "{\"id\":\"http://json-schema.org/draft-04/schema#\",\"$schema\":\"http://json-schema.org/draft-04/schema#\",\"description\":\"Core schema meta-schema\",\"definitions\":{\"schemaArray\":{\"type\":\"array\",\"minItems\":1,\"items\":{\"$ref\":\"#\"}},\"positiveInteger\":{\"type\":\"integer\",\"minimum\":0},\"positiveIntegerDefault0\":{\"allOf\":[{\"$ref\":\"#/definitions/positiveInteger\"},{\"default\":0}]},\"simpleTypes\":{\"enum\":[\"array\",\"boolean\",\"integer\",\"null\",\"number\",\"object\",\"string\"]},\"stringArray\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":1,\"uniqueItems\":true}},\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\",\"format\":\"uri\"},\"$schema\":{\"type\":\"string\",\"format\":\"uri\"},\"title\":{\"type\":\"string\"},\"description\":{\"type\":\"string\"},\"default\":{},\"multipleOf\":{\"type\":\"number\",\"minimum\":0,\"exclusiveMinimum\":true},\"maximum\":{\"type\":\"number\"},\"exclusiveMaximum\":{\"type\":\"boolean\",\"default\":false},\"minimum\":{\"type\":\"number\"},\"exclusiveMinimum\":{\"type\":\"boolean\",\"default\":false},\"maxLength\":{\"$ref\":\"#/definitions/positiveInteger\"},\"minLength\":{\"$ref\":\"#/definitions/positiveIntegerDefault0\"},\"pattern\":{\"type\":\"string\",\"format\":\"regex\"},\"additionalItems\":{\"anyOf\":[{\"type\":\"boolean\"},{\"$ref\":\"#\"}],\"default\":{}},\"items\":{\"anyOf\":[{\"$ref\":\"#\"},{\"$ref\":\"#/definitions/schemaArray\"}],\"default\":{}},\"maxItems\":{\"$ref\":\"#/definitions/positiveInteger\"},\"minItems\":{\"$ref\":\"#/definitions/positiveIntegerDefault0\"},\"uniqueItems\":{\"type\":\"boolean\",\"default\":false},\"maxProperties\":{\"$ref\":\"#/definitions/positiveInteger\"},\"minProperties\":{\"$ref\":\"#/definitions/positiveIntegerDefault0\"},\"required\":{\"$ref\":\"#/definitions/stringArray\"},\"additionalProperties\":{\"anyOf\":[{\"type\":\"boolean\"},{\"$ref\":\"#\"}],\"default\":{}},\"definitions\":{\"type\":\"object\",\"additionalProperties\":{\"$ref\":\"#\"},\"default\":{}},\"properties\":{\"type\":\"object\",\"additionalProperties\":{\"$ref\":\"#\"},\"default\":{}},\"patternProperties\":{\"type\":\"object\",\"additionalProperties\":{\"$ref\":\"#\"},\"default\":{}},\"dependencies\":{\"type\":\"object\",\"additionalProperties\":{\"anyOf\":[{\"$ref\":\"#\"},{\"$ref\":\"#/definitions/stringArray\"}]}},\"enum\":{\"type\":\"array\",\"minItems\":1,\"uniqueItems\":true},\"type\":{\"anyOf\":[{\"$ref\":\"#/definitions/simpleTypes\"},{\"type\":\"array\",\"items\":{\"$ref\":\"#/definitions/simpleTypes\"},\"minItems\":1,\"uniqueItems\":true}]},\"allOf\":{\"$ref\":\"#/definitions/schemaArray\"},\"anyOf\":{\"$ref\":\"#/definitions/schemaArray\"},\"oneOf\":{\"$ref\":\"#/definitions/schemaArray\"},\"not\":{\"$ref\":\"#\"}},\"dependencies\":{\"exclusiveMaximum\":[\"maximum\"],\"exclusiveMinimum\":[\"minimum\"]},\"default\":{}}"

let meta_schema_name = "_META_SCHEMA"

let register_meta_schema () =
  match rj_schema_exists meta_schema_name with
  | true -> return_unit
  | false ->
    let%lwt () = Logger.info "Loading meta schema" in
    begin match rj_register_schema meta_schema_name meta_schema with
      | None -> Logger.info "Loaded meta schema"
      | Some err -> fail_with err
    end

let create schema_name parallelism_threshold =
  Lwt_mutex.with_lock mutex_create (fun () ->
    let%lwt () = register_meta_schema () in
    let%lwt () = match rj_schema_exists schema_name with
      | true -> return_unit
      | false ->
        let path = sprintf "%s%s" Fs.conf_json_schemas_dir schema_name in
        let%lwt () = Logger.info (sprintf "Loading [%s]" path) in
        let%lwt contents = Lwt_io.chars_of_file path |> Lwt_stream.to_string in
        begin match validate_single meta_schema_name contents with
          | Error err -> fail_with err
          | Ok () ->
            begin match rj_register_schema schema_name contents with
              | Some err -> fail_with err
              | None -> Logger.info (sprintf "Loaded [%s]" path)
            end
        end
    in
    let instance = { schema_name; parallelism_threshold; } in
    return instance
  )

let validate instance msgs =
  let validator = match Collection.length msgs with
    | 1 ->
      let raw = Collection.to_list msgs |> snd |> List.hd_exn in
      fun () -> validate_single instance.schema_name raw
    | _ ->
      let raws = Collection.to_array msgs |> snd in
      fun () -> validate_multiple instance.schema_name raws
  in
  if (Collection.length msgs) >= instance.parallelism_threshold
  then Lwt_preemptive.detach validator ()
  else wrap validator
