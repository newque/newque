open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

(* let handler table ((ch, _) as conn) req body = *)
let handler table _ _ _ =
  let status = Code.status_of_code 200 in
  let body = match String.Table.find table "http8000" with
    | None -> "Can't find http8000"
    | Some listen ->
      begin match String.Table.find listen "example" with
        | None -> "Can't find example"
        | Some chan -> Sexp.to_string (Channel.sexp_of_t chan)
      end
  in
  Server.respond_string ~status ~body ()
