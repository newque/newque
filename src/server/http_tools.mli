open Cohttp

val call :
  ?ctx:Cohttp_lwt_unix_net.ctx ->
  ?headers:Header.t ->
  ?body:Cohttp_lwt_body.t ->
  ?chunked:bool ->
  timeout:float ->
  Code.meth ->
  Uri.t ->
  (Response.t * Cohttp_lwt_body.t) Lwt.t

val append_to_path : Uri.t -> string -> Uri.t
