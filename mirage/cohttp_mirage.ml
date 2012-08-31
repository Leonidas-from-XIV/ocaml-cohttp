(*
 * Copyright (c) 2012 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)

include Cohttp_mirage_raw
open Lwt

let stream_of_body read_fn ic =
  let fin = ref false in
  Lwt_stream.from (fun () ->
    match !fin with
    |true -> return None
    |false -> begin
      match_lwt read_fn ic with
      |Transfer.Done -> 
        return None
      |Transfer.Final_chunk c ->
        fin := true;
        return (Some c);
      |Transfer.Chunk c ->
        return (Some c)
    end
  )

let wait_for_stream st =
  let t,u = task () in
  Lwt_stream.on_terminate st (wakeup u);
  t

module Client = struct

  type response = (Response.response * string Lwt_stream.t option) option

  let write_request ?body req oc =
    Request.write (fun req oc ->
      match body with
      |None -> return ()
      |Some b -> Lwt_stream.iter_s (Request.write_body req oc) b
    ) req oc

  let read_response ?(close=false) ic oc =
    match_lwt Response.read ic with
    |None -> return None
    |Some res -> begin
      match Response.has_body res with
      |true ->
        let body = stream_of_body (Response.read_body res) ic in
        if close then
          Lwt_stream.on_terminate body (fun () ->
            Lwt.ignore_result (Net.Channel.TCPv4.close ic));
        return (Some (res, Some body))
      |false ->
        return (Some (res, None))
    end
 
  let call mgr ?headers ?body meth uri =
    let encoding = 
      match body with 
      |None -> Transfer.Fixed 0L 
      |Some _ -> Transfer.Chunked in
    let _ = Request.make ~meth ~encoding ?headers uri in
    (* TODO *)
    fail (Failure "todo")

  let head ?headers uri = call ?headers `HEAD uri 
  let get ?headers uri = call ?headers `GET uri 
  let delete ?headers uri = call ?headers `DELETE uri 
  let post ?headers ?body uri = call ?headers ?body `POST uri 
  let put ?headers ?body uri = call ?headers ?body `POST uri 

  let post_form ?headers ~params uri =
    let headers =
      match headers with
      |None -> Header.of_list ["content-type","application/x-www-form-urlencoded"]
      |Some h -> Header.add h "content-type" "application/x-www-form-urlencoded"
    in
    let body = Lwt_stream.of_list [(Uri.encoded_of_query (Header.to_list params))] in
    post ~headers ~body uri

  let callv mgr host port reqs =
    fail (Failure "todo")
end

module Server = struct

  type conn_id = int
  let string_of_conn_id = string_of_int
  type response = Response.response * string Lwt_stream.t option

  type config = {
    address: string;
    callback: conn_id -> ?body:string Lwt_stream.t -> Request.request -> response Lwt.t;
    conn_closed : conn_id -> unit -> unit;
    port: int;
    root_dir: string option;
    timeout: int option;
  }

  let respond_string ?headers ~status ~body () =
    let res = Response.make ~status 
      ~encoding:(Transfer.Fixed (Int64.of_int (String.length body))) ?headers () in
    let body = Some (Lwt_stream.of_list [body]) in
    return (res,body)

  let respond_error ~status ~body () =
    respond_string ~status ~body:("Error: "^body) ()

  let daemon_callback spec =
    let conn_id = ref 0 in
    let daemon_callback ic oc =
      let conn_id = incr conn_id; !conn_id in
      (* Read the requests *)
      let req_stream = Lwt_stream.from (fun () ->
        match_lwt Request.read ic with
        |Some req -> begin
          (* Ensure the input body has been fully read before reading again *)
          match Request.has_body req with
          |true ->
            let req_body = stream_of_body (Request.read_body req) ic in
            wait_for_stream req_body >>= fun () -> return (Some (req, Some req_body))
          |false -> return (Some (req, None))
        end
        |None -> return None
      ) in
      (* Map the requests onto a response stream to serialise out *)
      let res_stream = Lwt_stream.map_s (fun (req, body) -> 
        try_lwt 
          spec.callback conn_id ?body req
        with exn ->
          respond_error ~status:`Internal_server_error ~body:(Printexc.to_string exn) ()
      ) req_stream in
      (* Clean up resources when the response stream terminates and call
       * the user callback *)
      Lwt_stream.on_terminate res_stream (spec.conn_closed conn_id);
      (* Transmit the responses *)
      Lwt_stream.iter_s (fun (res, body) ->
        Response.write (fun res oc ->
          match body with
          |None -> return ()
          |Some b -> Lwt_stream.iter_s (Response.write_body res oc) b
        ) res oc
      ) res_stream
    in daemon_callback
 
  let main spec =
    let () = match spec.root_dir with Some dir -> Sys.chdir dir | None -> () in
    return () (* XXX TODO *)
end