type call =
  ?headers:Http.Header.t ->
  ?body:Body.t ->
  ?absolute_form:bool ->
  ?chunked:bool ->
  Http.Method.t ->
  Uri.t ->
  sw:Eio.Switch.t ->
  net:[ `Generic ] Eio.Net.ty Eio.Resource.t ->
  Http.Response.t * Body.t

module type Connection_cache = sig
  type t

  val call : t -> call
  (** Process a request. Please see {!type:call}. *)
end
