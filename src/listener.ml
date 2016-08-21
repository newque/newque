open Sexplib.Conv

type server =
  | HTTP of Http.t * unit Lwt.u sexp_opaque
  | ZMQ of unit * unit Lwt.u sexp_opaque
[@@deriving sexp_of]

type t = {
  id: string;
  server: server;
} [@@deriving sexp_of]
