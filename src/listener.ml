type protocol =
  | HTTP of Http.t
  | ZMQ of string ZMQ.Socket.t

type kind =
  | External of string
  | Internal

type t = {
  host: string;
  port: int;
  protocol: protocol;
  kind: kind;
}

let start prot_conf =
  let open Config_j in
  match prot_conf.protocol with
  | HTTP -> ()
  | _ -> failwith "Not implemented"
