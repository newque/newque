type t = {
  generic : Config_j.ext_listener;
  specific : Config_j.http_settings;
  sock : Lwt_unix.file_descr;
  close : unit Lwt.u;
  ctx : Cohttp_lwt_unix_net.ctx;
  thread : unit Conduit_lwt_unix.io;
}

val start : Config_j.ext_listener -> Config_j.http_settings -> t Conduit_lwt_unix.io

val stop : t -> unit Conduit_lwt_unix.io

val close : t -> unit Conduit_lwt_unix.io
