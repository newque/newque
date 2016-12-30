val default_perm : int

val log_dir : string
val conf_dir : string
val conf_chan_dir : string
val data_dir : string
val data_chan_dir : string

val healthy_fd : Lwt_unix.file_descr -> bool Lwt.t

val is_directory : ?create:bool -> string -> bool Lwt.t

val list_files : string -> string list Lwt.t
