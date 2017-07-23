val get_conn_pool :
  string ->
  int ->
  auth:string option ->
  database:int ->
  pool_size:int ->
  info:Log.simple_logging ->
  Redis_lwt.Client.connection Lwt_pool.t

val exec_script :
  Redis_lwt.Client.connection ->
  string ->
  keys:string list ->
  args:string list ->
  debug:Log.lazy_logging ->
  Redis_lwt.Client.reply Lwt.t

val debug_reply :
  ?nested:bool ->
  Redis_lwt.Client.reply ->
  string
