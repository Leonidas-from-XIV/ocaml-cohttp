module Make_no_cache : sig
  include S.Connection_cache

  val create :
    https:
      (Uri.t ->
      [ `Generic ] Eio.Net.stream_socket_ty Eio.Resource.t ->
      _ Eio.Flow.two_way)
      option ->
    unit ->
    t
end
