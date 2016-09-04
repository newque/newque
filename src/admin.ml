open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

(* let handler ((ch, _) as conn) req body = *)
let handler _ _ _ =
  let status = Code.status_of_code 200 in
  let body = "Hello Admin!" in
  Server.respond_string ~status ~body ()
