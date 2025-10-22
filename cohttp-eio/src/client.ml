open Eio.Std

type connection = Eio.Flow.two_way_ty r

module No_cache = Connection_cache.Make_no_cache

let cache = ref No_cache.(create ~https:None () |> call)
let set_cache c = cache := c

type t = { net : [ `Generic ] Eio.Net.ty Eio.Resource.t }

include
  Cohttp.Generic.Client.Make
    (struct
      type 'a io = 'a
      type body = Body.t
      type 'a with_context = t -> sw:Eio.Switch.t -> 'a

      let map_context v f t ~sw = f (v t ~sw)

      let call (t : t) ~sw ?headers ?body ?chunked meth uri =
        let net = t.net in
        !cache ?headers ?body ?chunked ~absolute_form:false meth uri ~sw ~net
    end)
    (Io.IO)

(* let make_generic fn = (fn :> t) *)

let make ~https net : t =
  let net = (net :> [ `Generic ] Eio.Net.ty r) in
  let _https =
    (https
      :> (Uri.t -> [ `Generic ] Eio.Net.stream_socket_ty r -> connection) option)
  in
  { net }
