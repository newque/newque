open Core.Std

type t = string

let uuid () = Uuidm.to_string (Uuidm.v `V4)
let uuid_bytes () = Uuidm.to_bytes (Uuidm.v `V4)

let default_separator = ","

let array_random length = Array.init length ~f:(fun _ -> uuid ())

let array_of_string_opt ?(sep=default_separator) ~mode ~length_none opt =
  match opt with
  | None -> Ok (array_random length_none)
  | Some header ->
    if String.is_empty header then
      Error "Message ID header exists, but is empty."
    else begin match mode with
      | `Single | `Atomic -> Ok [| header |]
      | `Multiple ->
        let ids = Array.of_list (Util.split ~sep header) in
        begin match Array.exists ~f:String.is_empty ids with
          | true -> Error "IDs cannot be empty strings."
          | false -> Ok ids
        end
    end
