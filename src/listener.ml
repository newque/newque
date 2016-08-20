type server =
  | HTTP of Http.t * unit Lwt.u
  | ZMQ of unit * unit Lwt.u

type t = {
  id: string;
  server: server;
}
