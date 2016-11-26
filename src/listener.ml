open Core.Std

type server =
  | HTTP of Http_prot.t * unit Lwt.u sexp_opaque
  | ZMQ of Zmq_prot.t * unit Lwt.u sexp_opaque
  | Private
[@@deriving sexp_of]

type t = {
  id: string;
  server: server;
} [@@deriving sexp_of]

let get_prot listener = match listener.server with
  | HTTP _ -> "HTTP"
  | ZMQ _ -> "ZMQ"
  | Private -> "Internal"

let private_listener = {
  id = "";
  server = Private;
}
