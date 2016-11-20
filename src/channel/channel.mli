type t = {
  name : string;
  endpoint_names : string list;
  push : Message.t -> Id.t array -> int Lwt.t;
  pull_slice : int64 -> mode:Mode.Read.t -> only_once:bool -> Persistence.slice Lwt.t;
  pull_stream : int64 -> mode:Mode.Read.t -> only_once:bool -> string Lwt_stream.t Lwt.t;
  size : unit -> int64 Lwt.t;
  raw: bool;
  read: Read_settings.t option;
  write : Write_settings.t option;
  separator : string;
  buffer_size : int;
  max_read: int64;
} [@@deriving sexp]

val create : string -> Config_t.config_channel -> t

val push : t -> Message.t -> Id.t array -> int Lwt.t

val pull_slice : t -> mode:Mode.Read.t -> limit:int64 -> only_once:bool -> Persistence.slice Lwt.t

val pull_stream : t -> mode:Mode.Read.t -> only_once:bool -> string Lwt_stream.t Lwt.t

val size : t -> unit -> int64 Lwt.t
