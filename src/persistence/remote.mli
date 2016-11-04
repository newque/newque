module M : Persistence.Template

val create :
  string array ->
  input:Config_t.config_channel_format ->
  output:Config_t.config_channel_format ->
  M.t Lwt.t

val read_batch_size : int
