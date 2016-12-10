module M : Persistence.Template

val create : string array ->
  index:string ->
  typename:string ->
  float ->
  M.t Lwt.t
