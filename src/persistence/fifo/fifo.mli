module M : Persistence.Template

val create :
  chan_name:string ->
  host:string ->
  port:int ->
  timeout_ms:float ->
  health_time_limit_ms:float ->
  M.t Lwt.t
