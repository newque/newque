module M : Persistence.Template

val create :
  chan_name:string ->
  host:string ->
  port:int ->
  socket_settings:Config_t.zmq_socket_settings option ->
  M.t Lwt.t
