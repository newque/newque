open Core.Std

type t = string

let uuid () = Uuidm.to_string (Uuidm.v `V4)
let uuid_bytes () = Uuidm.to_bytes (Uuidm.v `V4)

let default_separator = ","
let default_splitter = Util.make_splitter ~sep:default_separator

let coll_random length = Collection.of_array (Array.init length ~f:(fun _ -> uuid ()))

let coll_of_string_opt ?(splitter=default_splitter) ~mode ~length_none opt =
  match opt with
  | None -> Ok (coll_random length_none)
  | Some header ->
    if String.is_empty header then
      Error "Message ID header exists, but is empty."
    else begin match mode with
      | `Single | `Atomic -> Ok (Collection.singleton header)
      | `Multiple ->
        let ids = splitter header in
        begin match List.exists ~f:String.is_empty ids with
          | true -> Error "IDs cannot be empty strings."
          | false -> Ok (Collection.of_list ids)
        end
    end
