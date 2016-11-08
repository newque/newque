module M : Persistence.Template

val create :
  string array ->
  Config_t.pair list ->
  input:Config_t.config_channel_format ->
  output:Config_t.config_channel_format ->
  chan_separator: string ->
  M.t Lwt.t

val read_batch_size : int
