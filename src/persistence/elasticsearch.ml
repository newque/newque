open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

module Logger = Log.Make (struct let path = Log.outlog let section = "Elasticsearch" end)

type elasticsearch_t = {
  base_urls: Uri.t array;
  index: string;
  typename: string;
} [@@deriving sexp]

let get_base instance =
  let arr = instance.base_urls in
  Array.get arr (Random.int (Array.length arr))

let create base_urls ~index ~typename =
  let instance = {
    base_urls = Array.map ~f:Uri.of_string base_urls;
    index = String.lowercase index;
    typename = String.lowercase typename;
  }
  in
  return instance

module M = struct

  type t = elasticsearch_t [@@deriving sexp]

  let close instance = return_unit

  let push instance ~msgs ~ids =
    let open Json_obj_j in
    let uri = Util.append_to_path (get_base instance) (Printf.sprintf "%s/_bulk" instance.index) in
    let bulk_format = Array.concat_mapi msgs ~f:(fun i msg ->
        let json = `Assoc [
            "index", `Assoc [
              "_index", `String instance.index;
              "_type", `String instance.typename;
              "_id", `String (Array.get ids i);
            ]
          ] in
        [| Yojson.Basic.to_string json; "\n"; msg; "\n" |]
      ) in
    let body = Cohttp_lwt_body.of_stream (Lwt_stream.of_array bulk_format) in
    let%lwt (response, body) = Client.call ~body ~chunked:false `POST uri in
    let%lwt body_str = Cohttp_lwt_body.to_string body in
    let open Yojson.Basic.Util in
    let json = Yojson.Basic.from_string body_str in
    match json |> member "errors" with
    | `Bool false ->
      let%lwt parsed = Util.parse_json_lwt bulk_response_of_string body_str in
      let total = List.fold_left parsed.items ~init:0 ~f:(fun acc item ->
          if Int.(=) item.index.status 201 then (succ acc) else acc
        )
      in
      return total
    | `Bool true ->
      let%lwt () = Logger.error body_str in
      wrap (fun () ->
        let items = json |> member "items" |> to_list in
        let strings = List.filter_map items ~f:(fun item ->
            match item |> member "index" |> member "error" with
            | `Null -> None
            | error_obj ->
              let err_type = error_obj |> member "type" |> to_string_option |> Option.value ~default:"" in
              let err_reason = error_obj |> member "reason" |> to_string_option |> Option.value ~default:"" in
              begin match error_obj |> member "caused_by" with
                | `Null -> Some (Printf.sprintf "%s %s" err_type err_reason)
                | caused_by_obj ->
                  let caused_type = caused_by_obj |> member "type" |> to_string_option |> Option.value ~default:"" in
                  let caused_reason = caused_by_obj |> member "reason" |> to_string_option |> Option.value ~default:"" in
                  Some (Printf.sprintf "%s %s %s %s" err_type err_reason caused_type caused_reason)
              end
          )
        in
        failwith (Printf.sprintf "ES errors: [%s]" (String.concat ~sep:", " strings))
      )
    | err -> fail_with (Printf.sprintf "Incorrect ES bulk json: %s" body_str)

  let pull instance ~search ~fetch_last = fail_with "Unimplemented: ES pull"

  let size instance =
    let open Json_obj_j in
    let uri = Util.append_to_path (get_base instance) (Printf.sprintf "%s/_count" instance.index) in
    let%lwt (response, body) = Client.call ~chunked:false `GET uri in
    let%lwt body_str = Cohttp_lwt_body.to_string body in
    begin match Code.code_of_status (Response.status response) with
      | 200 ->
        let%lwt parsed = Util.parse_json_lwt es_size_of_string body_str in
        return parsed.es_count
      | code ->
        let%lwt () = Logger.error body_str in
        failwith (Printf.sprintf "Couldn't get count from ES (HTTP %s)" (Code.string_of_status (Response.status response)))
    end

  let delete instance = fail_with "Unimplemented: ES delete"

  let health instance =
    let uri = Util.append_to_path (get_base instance) (Printf.sprintf "%s/_stats/docs" instance.index) in
    try%lwt
      let%lwt (response, body) = Client.call ~chunked:false `GET uri in
      let%lwt body_str = Cohttp_lwt_body.to_string body in
      begin match Code.code_of_status (Response.status response) with
        | 200 -> return []
        | code ->
          let%lwt () = Logger.error body_str in
          return [
            Printf.sprintf
              "Couldn't validate index [%s] at %s (HTTP %s)"
              instance.index (Uri.to_string uri) (Code.string_of_status (Response.status response))
          ]
      end
    with
    | Unix.Unix_error (c, n, _) -> return [Fs.format_unix_exn c n (Uri.to_string uri)]
    | err -> return [Exn.to_string err]

end
