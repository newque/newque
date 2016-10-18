open Core.Std

type t = string

let time_ns () = Time_ns.now () |> Time_ns.to_int63_ns_since_epoch |> Int63.to_int64

let uuid () = Uuidm.v `V4 |> Uuidm.to_string

let array_of_header ?(sep=",") ~mode ~msgs header_option =
  match header_option with
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
        let empty_strings = Array.exists ~f:String.is_empty ids in
        begin match (empty_strings, (Array.length ids), (Array.length msgs)) with
          | (true, _, _) -> Error "IDs cannot be empty strings."
          | (false, id_count, msg_count) when id_count = msg_count -> Ok ids
          | (false, id_count, msg_count) ->
            Error (Printf.sprintf "Mismatch between the number of IDs (%d) and the number of messages (%d)" id_count msg_count)
        end
    end

let to_string x = x
