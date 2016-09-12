open Core.Std

type t = string

let time_ns () = Time_ns.now () |> Time_ns.to_int63_ns_since_epoch |> Int63.to_int64

let uuid () = Uuidm.v `V4 |> Uuidm.to_bytes

let rev_list_of_header ?(sep=",") ~mode ~msgs header_option =
  match header_option with
  | None ->
    begin match mode with
      | `Single | `Atomic -> Ok [uuid ()]
      | `Multiple -> Ok (List.init (List.length msgs) ~f:(fun _ -> uuid ()))
    end
  | Some header ->
    if String.is_empty header then
      Error "Message ID header exists, but is empty."
    else begin match mode with
      | `Single | `Atomic -> Ok [header]
      | `Multiple ->
        let ids = Util.split ~sep header in
        let empty = List.filter ~f:String.is_empty ids in
        begin match ((List.is_empty empty), (List.length ids), (List.length msgs)) with
          | (false, _, _) -> Error "IDs cannot be empty strings."
          | (true, id_count, msg_count) when id_count = msg_count -> Ok (List.rev ids)
          | (true, id_count, msg_count) ->
            Error (Printf.sprintf "Mismatch between the number of IDs (%d) and the number of messages (%d)" id_count msg_count)
        end
    end

let to_string x = x
