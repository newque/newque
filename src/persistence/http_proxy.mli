module M : Persistence.Template

val create :
  string array ->
  Config_t.pair list ->
  float ->
  input:Config_t.config_channel_format ->
  output:Config_t.config_channel_format ->
  chan_separator: string ->
  M.t Lwt.t
