open Core
open Lwt
open Cohttp
open Cohttp_lwt_unix
open Routing

module Logger = Log.Make (struct let section = "Admin" end)

(* let handler routing ((ch, _) as conn) req body = *)
let handler routing _ req _ =
  let meth = Request.meth req in
  let path = Uri.path (Request.uri req) in
  let url_fragments = String.split ~on:'/' path in
  let%lwt code, result = try%lwt
      begin match meth, url_fragments with
        | `GET, ""::"listeners"::_ ->
          return (200, Ok ["listeners", (routing.listeners_by_port None)])

        | `GET, ""::"channels"::chan_name::_ ->
          let%lwt channels = routing.channels_by_name (Some chan_name) in
          return (200, Ok ["channels", channels])

        | `GET, ""::"channels"::_ ->
          let%lwt channels = routing.channels_by_name None in
          return (200, Ok ["channels", channels])

        | _ ->
          return (404, Error [sprintf "Invalid path %s" path])
      end
    with
    | ex -> return (500, Error (Exception.human_list ex))
  in
  let pairs = match result with
    | Ok pairs -> pairs
    | Error errors -> ["errors", `List (List.map errors ~f:(fun x -> `String x))]
  in
  let headers = Header.of_list [
      "content-type", "application/json"
    ]
  in
  let status = Code.status_of_code code in
  let body = Yojson.Basic.pretty_to_string (`Assoc (("code", `Int code)::pairs)) in
  Server.respond_string ~headers ~status ~body ()
