module M : Persistence.Template

val create :
  chan_name:string ->
  host:string ->
  port:int ->
  socket_settings:Config_t.zmq_socket_settings option ->
  timeout_ms:float ->
  health_time_limit_ms:float ->
  M.t Lwt.t
