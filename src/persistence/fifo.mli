module M : Persistence.Template

val create :
  chan_name:string ->
  string ->
  int ->
  float ->
  M.t Lwt.t
