open Core.Std
open Lwt
open Cohttp
open Cohttp_lwt_unix

let call ?ctx ?headers ?body ?chunked ~timeout meth uri =
  let thread = Client.call ?ctx ?headers ?body ?chunked meth uri in
  try%lwt
    pick [thread; Lwt_unix.timeout timeout]
  with
  | Lwt_unix.Timeout ->
    fail_with (sprintf
        "No response from upstream [HTTP %s %s] within %F seconds"
        (Code.string_of_method meth) (Uri.to_string uri) timeout
    )
  | ex ->
    fail_with (sprintf
        "[%s %s] %s"
        (Code.string_of_method meth) (Uri.to_string uri) (Exception.human ex)
    )

let append_to_path uri append =
  let base_path = Uri.path uri in
  if String.(=) (String.suffix base_path 1) "/"
  then Uri.with_path uri (sprintf "%s%s" base_path append)
  else Uri.with_path uri (sprintf "%s/%s" base_path append)
