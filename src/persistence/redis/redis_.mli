module M : Persistence.Template

val create :
  chan_name:string ->
  string ->
  int ->
  auth:(string option) ->
  database:int ->
  pool_size:int ->
  M.t Lwt.t
