open Core.Std

type server =
  | HTTP of Http.t * unit Lwt.u sexp_opaque
  | ZMQ of unit * unit Lwt.u sexp_opaque
  | Private
[@@deriving sexp_of]

type t = {
  id: string;
  server: server;
} [@@deriving sexp_of]

let private_listener = {
  id = "";
  server = Private;
}
