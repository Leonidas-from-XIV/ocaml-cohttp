type t

val create :
  ?all_proxy:Uri.t ->
  ?scheme_proxy:(string * Uri.t) list ->
  ?no_proxy:string ->
  ?proxy_headers:Http.Header.t ->
  unit ->
  t
