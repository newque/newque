open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

module Logger = Log.Make (struct let section = "Elasticsearch" end)

type elasticsearch_t = {
  base_urls: Uri.t array;
  index: string;
  typename: string;
  timeout: float; (* in seconds *)
}

let get_base instance =
  let arr = instance.base_urls in
  Array.get arr (Random.int (Array.length arr))

let create base_urls ~index ~typename timeout_ms =
  let instance = {
    base_urls = Array.map ~f:Uri.of_string base_urls;
    index = String.lowercase index;
    typename = String.lowercase typename;
    timeout = Float.(/) timeout_ms 1000.;
  }
  in
  return instance

module M = struct

  type t = elasticsearch_t

  let close instance = return_unit

  let push instance ~msgs ~ids =
    let open Json_obj_j in
    let uri = Http_tools.append_to_path (get_base instance) (sprintf "%s/_bulk" instance.index) in

    let bulk_format = Collection.concat_mapi_two msgs ids ~f:(fun i msg id ->
        let json = `Assoc [
            "index", `Assoc [
              "_index", `String instance.index;
              "_type", `String instance.typename;
              "_id", `String id;
            ]
          ]
        in
        [ Yojson.Basic.to_string json; "\n"; msg; "\n" ]
      )
    in
    let stream = match Collection.to_list_or_array bulk_format with
      | `List bulk -> Lwt_stream.of_list bulk
      | `Array bulk -> Lwt_stream.of_array bulk
    in
    let body = Cohttp_lwt_body.of_stream stream in

    let%lwt (response, body) = Http_tools.call ~body ~chunked:false ~timeout:instance.timeout `POST uri in
    let%lwt body_str = Cohttp_lwt_body.to_string body in
    let open Yojson.Basic.Util in
    let json = Yojson.Basic.from_string body_str in
    match json |> member "errors" with
    | `Bool false ->
      let parsed = bulk_response_of_string body_str in
      let total = List.fold_left parsed.items ~init:0 ~f:(fun acc item ->
          if Int.(=) item.index.status 201 then (succ acc) else acc
        )
      in
      return total
    | `Bool true ->
      let%lwt () = Logger.error (sprintf "[%s] ES errors: %s" (Uri.to_string uri) body_str) in
      wrap (fun () ->
        let items = json |> member "items" |> to_list in
        let strings = List.filter_map items ~f:(fun item ->
            match item |> member "index" |> member "error" with
            | `Null -> None
            | error_obj ->
              let err_type = error_obj |> member "type" |> to_string_option |> Option.value ~default:"" in
              let err_reason = error_obj |> member "reason" |> to_string_option |> Option.value ~default:"" in
              begin match error_obj |> member "caused_by" with
                | `Null -> Some (sprintf "%s %s" err_type err_reason)
                | caused_by_obj ->
                  let caused_type = caused_by_obj |> member "type" |> to_string_option |> Option.value ~default:"" in
                  let caused_reason = caused_by_obj |> member "reason" |> to_string_option |> Option.value ~default:"" in
                  Some (sprintf "%s %s %s %s" err_type err_reason caused_type caused_reason)
              end
          )
        in
        failwith (sprintf "[%s] ES errors: %s" (Uri.to_string uri) (String.concat ~sep:", " strings))
      )
    | _ -> fail_with (sprintf "Incorrect ES bulk json: %s" body_str)

  let pull instance ~search ~fetch_last = fail_with "Unimplemented: ES read"

  let size instance =
    let open Json_obj_j in
    let uri = Http_tools.append_to_path (get_base instance) (sprintf "%s/_count" instance.index) in
    let%lwt (response, body) = Http_tools.call ~chunked:false ~timeout:instance.timeout `GET uri in
    let%lwt body_str = Cohttp_lwt_body.to_string body in
    begin match Code.code_of_status (Response.status response) with
      | 200 ->
        let parsed = es_size_of_string body_str in
        return parsed.es_count
      | code ->
        let%lwt () = Logger.error body_str in
        failwith (sprintf
            "[%s] Couldn't get count from ES (HTTP %s)"
            (Uri.to_string uri) (Code.string_of_status (Response.status response))
        )
    end

  let delete instance = fail_with "Unimplemented: ES delete"

  let health instance =
    let uri = Http_tools.append_to_path (get_base instance) (sprintf "%s/_stats/docs" instance.index) in
    try%lwt
      let%lwt (response, body) = Http_tools.call ~chunked:false ~timeout:instance.timeout `GET uri in
      let%lwt body_str = Cohttp_lwt_body.to_string body in
      begin match Code.code_of_status (Response.status response) with
        | 200 -> return []
        | code ->
          let%lwt () = Logger.error body_str in
          return [
            sprintf
              "[%s] Couldn't validate index [%s] (HTTP %s)"
              (Uri.to_string uri) instance.index
              (Code.string_of_status (Response.status response))
          ]
      end
    with
    | ex -> return (Exception.human_list ex)

end
