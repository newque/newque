type t = {
  name : string;
  endpoint_names : string list;
  push : Message.t array -> Id.t array -> Ack.t -> int Lwt.t;
  pull_slice : int64 -> mode:Mode.Read.t -> string array Lwt.t;
  pull_stream : int64 -> mode:Mode.Read.t -> string Lwt_stream.t Lwt.t;
  size : unit -> int64 Lwt.t;
  ack : Ack.t;
  separator : string;
  buffer_size : int;
  max_read: int64;
} [@@deriving sexp]

val create : ?redis:Config_t.config_redis -> string -> Config_t.config_channel -> t

val push : t -> Message.t array -> Id.t array -> int Lwt.t

val pull_slice : t -> mode:Mode.Read.t -> string array Lwt.t

val pull_stream : t -> mode:Mode.Read.t -> string Lwt_stream.t Lwt.t

val size : t -> unit -> int64 Lwt.t
