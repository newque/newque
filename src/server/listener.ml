open Core.Std

type server =
  | HTTP of Http_prot.t * unit Lwt.u
  | ZMQ of Zmq_prot.t * unit Lwt.u
  | Private

type t = {
  id: string;
  server: server;
}

let get_prot listener = match listener.server with
  | HTTP _ -> "http"
  | ZMQ _ -> "zmq"
  | Private -> "<internal>"

let private_listener = {
  id = "<internal>";
  server = Private;
}
