(* Copyright 2001, 2002 b8_bavard, b8_fee_carabine, INRIA *)
(*
    This file is part of mldonkey.

    mldonkey is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    mldonkey is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mldonkey; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)

open Printf2
open Md4

open CommonShared
open CommonServer
open CommonComplexOptions
open GuiProto
open CommonClient
open CommonFile
open CommonUser
open CommonSearch
open CommonTypes
open Options
open BasicSocket
open TcpBufferedSocket
open DonkeyMftp
open DonkeyOneFile
open DonkeyProtoCom
open DonkeyTypes
open DonkeyGlobals
open DonkeyComplexOptions
open DonkeyOptions
open CommonOptions
open DonkeyClient  
open CommonGlobals
open DonkeyStats

module Udp = DonkeyProtoUdp 

let search_handler s t =
  let waiting = s.search_waiting - 1 in
  s.search_waiting <- waiting;
  List.iter (fun f ->
      search_found false s f.f_md4 f.f_tags
  ) t
(*  search.search_handler (Waiting s.search_waiting) *)
    
let make_xs ss =
  if !verbose then lprintf "******** make_xs ********\n";
   if ss.search_num <> !xs_last_search then
     begin
      xs_last_search := ss.search_num;
      xs_servers_list := Hashtbl2.to_list servers_by_key;
    end;

   let cut_for_udp_send max_servers list =
     let min_last_conn = last_time () - 8 * 3600 in
     let rec iter list n left =
       if n = 0 then
       left, list
       else
       match list with
           [] -> left, []
         | s :: tail ->
               if connection_last_conn s.server_connection_control > min_last_conn then
               iter tail (n-1) (s :: left)
               else
               iter tail n left in
     iter list max_servers [] in
  let before, after = cut_for_udp_send !!max_xs_packets !xs_servers_list in
  xs_servers_list := after;

   List.iter (fun s ->
      match s.server_sock with
           Connection _ -> ()
       | _ ->
             let module M = DonkeyProtoServer in
             let module Q = M.Query in
             udp_server_send s (
(* By default, send the MultipleUdp !!! we have to set 
server_send_multiple_replies to true by default, and change it to false
when receiving an old ping.

  if server_send_multiple_replies s then
              Udp.QueryUdpReq ss.search_query
         else *)
             Udp.QueryMultipleUdpReq ss.search_query);
  ) before;

  if !verbose then lprintf "===================== STARTING SEARCH ON OVERNET =========\n";
  DonkeyProtoOvernet.Overnet.overnet_search ss;
  DonkeyProtoKademlia.Kademlia.overnet_search ss
          
 let extent_search () =
  try
    if !xs_last_search >= 0 then  begin
       try
         make_xs (search_find !xs_last_search)
       with _ -> ()
    end;

  with e ->
     if !verbose then lprintf "extent_search: %s\n" (Printexc2.to_string e)

let add_user_friend s u = 
  let kind  = 
    if Ip.valid u.user_ip && ip_reachable u.user_ip then
      Direct_address (u.user_ip, u.user_port)
     else
      begin
        ( match s.server_sock, server_state s with
              Connection sock, (Connected _ |Connected_downloading _) ->
              query_id s.server_ip s.server_port (id_of_ip u.user_ip)
            | _ -> () );
      Invalid_address (u.user_name, Md4.to_string u.user_md4)
      end
  in
  let c = new_client kind  in
  c.client_tags <- u.user_tags;
  set_client_name c u.user_name u.user_md4;
  friend_add c

  

let udp_client_handler t p =
  if !verbose_udp then
    lprintf "Received UDP message:\n%s\n" (Udp.print t);

  let udp_from_server p =
    match p.UdpSocket.udp_addr with
      | Unix.ADDR_INET(ip, port) ->
	  let ip = Ip.of_inet_addr ip in
	  if !!update_server_list then
            let s = check_add_server ip (port-4) in
	    (* set last_conn, but add a 2 minutes offset to prevent 
	       staying connected to this server *)
            connection_set_last_conn s.server_connection_control (
              last_time () - 121);
            s.server_score <- s.server_score + 3;
            s
	  else 
	    find_server ip (port-4)
      | _ -> raise Not_found
  in
  match t with
      Udp.QueryLocationReplyUdpReq t ->
	(*      lprintf "Received location by UDP"; lprint_newline ();  *)
	let  s = udp_from_server p in
	List.iter (query_locations_reply s) t
      
  | Udp.QueryReplyUdpReq t ->
      (*      lprintf "Received file by UDP"; lprint_newline ();  *)
      if !xs_last_search >= 0 then
        let ss = search_find !xs_last_search in
	let s = udp_from_server p in
	List.iter (fun t ->
          Hashtbl.add udp_servers_replies t.f_md4 s;
          search_handler ss [t]
        ) t

  | Udp.PingServerReplyUdpReq t ->
      let module M = Udp.PingServerReplyUdp in
      let s = udp_from_server p in
      UdpSocket.declare_pong s.server_ip;
      s.server_last_message <- last_time ();
      s.server_nfiles <- Int64.of_int t.M.files;
      s.server_nusers <- Int64.of_int t.M.users;
      (match t.M.max_users with 
	   Some x -> s.server_max_users <- x
	 | None -> ());
      (match t.M.flags with 
	   Some x -> s.server_flags <- x
	 | None -> ())

  | Udp.EmuleReaskFilePingUdpReq t -> ()
      
      
  | _ -> 
      if !verbose_unexpected_messages then
      lprintf "Unexpected UDP message: \n%s\n"
        (DonkeyProtoUdp.print t)