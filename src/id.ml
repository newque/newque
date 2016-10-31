open Core.Std

type t = string

let time_ns () = Int63.to_int64 (Time_ns.to_int63_ns_since_epoch (Time_ns.now ()))

let uuid () = Uuidm.to_string (Uuidm.v `V4)

let array_of_string_opt ?(sep=",") ~mode ~msgs opt =
  match opt with
  | None ->
    begin match mode with
      | `Single | `Atomic -> Ok [| uuid () |]
      | `Multiple -> Ok (Array.init (Array.length msgs) ~f:(fun _ -> uuid ()))
    end
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

let to_string x = x

let of_string x = x
