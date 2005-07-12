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

open Int64ops
open AnyEndian
open Printf2
open Md4
open CommonTypes
open LittleEndian
open CommonGlobals
  
open DonkeyTypes
open DonkeyMftp
  
let emule_version b1 b2 b3 b4 b5 =
  let s = Printf.sprintf "%s"
    (string_of_int(int_of_string("0b" ^
    (Misc.dec2bin (int_of_string b1) 8) ^
    (Misc.dec2bin (int_of_string b2) 7) ^
    (Misc.dec2bin (int_of_string b3) 7) ^
    (Misc.dec2bin (int_of_string b4) 3) ^
    (Misc.dec2bin (int_of_string b5) 7))))
  in s

(* TODO : update this
I downgraded some of those to get better results :
We don't use emule udp extension, client_md4 in sourceexchange or complete sources in
file request *)
let mldonkey_emule_proto = {
    emule_comments = 1;
    emule_version = (int_of_string (emule_version "10" Autoconf.sub_version1 Autoconf.sub_version2 "0" "0"));
      (* first parameter means compatibleclient, MLDonkeys value is 10 *)
    emule_release = "";
    emule_secident = 0;
    emule_noviewshared = 0;
    emule_supportpreview = 0;
    emule_compression = if Autoconf.has_zlib then 1 else 0; (* 1 *)
    emule_sourceexchange = 1; (* 2 : +client_md4 3 : +IdHybrid (emule Kademlia?)*)
    emule_multipacket = 0; (* 1 *)
    emule_extendedrequest = 1; (* 1: +file_status 2: +ncomplete_sources*)
    emule_features = 0; (* 3 *)
    emule_udpver = 0; (* 4 *)
  }
  
let emule_miscoptions1 m = 
  let o = 
    (m.emule_udpver lsl 24) lor
    (m.emule_compression lsl 20) lor
    (m.emule_secident lsl 16) lor
    (m.emule_sourceexchange lsl 12) lor
    (m.emule_extendedrequest lsl 8) lor
    (m.emule_comments lsl 4) lor
    (m.emule_noviewshared lsl 2) lor
    (m.emule_multipacket lsl 1) lor
    (m.emule_supportpreview lsl 0)
  in
  Int64.of_int o
  
let update_emule_proto_from_miscoptions1 m o =
  let o = Int64.to_int o in
  m.emule_udpver <- (o lsr 24) land 0xf;
  m.emule_compression <- (o lsr 20) land 0xf;
  m.emule_secident <- (o lsr 16) land 0xf;
  m.emule_sourceexchange <- (o lsr 12) land 0xf;
  m.emule_extendedrequest <- (o lsr 8) land 0xf;
  m.emule_comments <- (o lsr 4) land 0xf;
  m.emule_noviewshared <- (o lsr 2) land 0x1;
  m.emule_udpver <- (o lsr 1) land 0x1;
  m.emule_udpver <- (o lsr 0) land 0x1
  
let extendedrequest e = 
  min e.emule_extendedrequest mldonkey_emule_proto.emule_extendedrequest
  
let sourceexchange e = 
  min e.emule_sourceexchange mldonkey_emule_proto.emule_sourceexchange

(*
BAD MESSAGE FROM CONNECTING CLIENT
UnknownReq:
ascii: [(1)(16)(231)(129)(131)(26) O(247)(154)(145)(251)(253)(167) G }(207) j(146)(140) { l(139) F(18)(0)(0)(0)(0)(0)(0)(0)(0)(0)(0)]
dec: [
(1)
(16)
(231)(129)(131)(26)(79)(247)(154)(145)(251)(253)(167)(71)(125)(207)(106)(146)
(140)(123)(108)(139)
(70)(18)
(0)(0)(0)(0)
(0)(0)(0)(0)(0)(0)
]



  *)
  
module Connect  = struct
    type t = {
        md4 : Md4.t;
        version : int;
        ip: Ip.t;
        port: int;
        tags : tag list;
        server_info : (Ip.t * int) option;
        left_bytes: string;
      }
    
    let names_of_tag =
      [
        "\001", Field_UNKNOWN "name";
        "\017", Field_UNKNOWN "version";
        "\015", Field_UNKNOWN "port";
        "\031", Field_UNKNOWN "udpport";
        "\060", Field_UNKNOWN "downloadtime";
        "\061", Field_UNKNOWN "incompleteparts";
        "\085", Field_UNKNOWN "mod_version";
        "\249", Field_UNKNOWN "emule_udpports";
        "\250", Field_UNKNOWN "emule_miscoptions1";
        "\251", Field_UNKNOWN "emule_version";
      ]
      
    let parse len s =
      let version = get_uint8 s 1 in
      let md4 = get_md4 s 2 in
      let ip = get_ip s 18 in
      let port = get_port s 22 in
(*      lprintf "port: %d" port; lprint_newline (); *)
      let tags, pos = get_tags s 24 names_of_tag in
      let len = String.length s in
      let server_info = 
        Some (get_ip s pos, get_port s (pos+4)) 
      in
      let left_bytes = String.sub s (pos+6) (String.length s - pos - 6) in
      {
        md4 = md4;
        version = version;
        ip = ip;
        port = port;
        tags = tags;
        server_info = server_info;
        left_bytes = left_bytes;
      }
    
    let print t = 
      lprintf "Connect (version %d) from [%s:%d] MD4: %s"
        t.version
        (Ip.to_string t.ip)
	t.port
        (Md4.to_string t.md4);
      (match t.server_info with
          None -> lprintf_nl ""
        | Some (ip, port) ->
            lprintf_nl " on server: %s:%d" (Ip.to_string ip) port);
      lprintf "tags: ";
      print_tags t.tags;
      if String.length t.left_bytes <> 0 then begin
        lprintf "  left bytes = ";
        String.iter (fun c -> lprintf "(%d)" (int_of_char c))
        t.left_bytes  end

    let write buf t =
      buf_int8 buf t.version;
      buf_md4 buf t.md4;
      buf_ip buf t.ip;
      buf_port buf t.port;
      buf_tags buf t.tags names_of_tag;
      begin
        match t.server_info with
          None -> 
            buf_ip buf Ip.null;
            buf_port buf 0
        | Some (ip, port) ->
            buf_ip buf ip;
            buf_port buf port;
      end;
      Buffer.add_string buf t.left_bytes

  end

module ConnectReply  = struct
    open Connect
    type t = Connect.t
      
    let parse len s =
      let version = get_uint8 s 1 in
      let md4 = get_md4 s 2 in
      let ip = get_ip s 18 in
      let port = get_port s 22 in
      let tags, pos = get_tags s 24 names_of_tag in
      let len = String.length s in
      let server_info = 
        Some (get_ip s pos, get_port s (pos+4)) 
      in
      let left_bytes = String.sub s (pos+6) (String.length s - pos - 6) in
      {
        md4 = md4;
        version = version;
        ip = ip;
        port = port;
        tags = tags;
        server_info = server_info;
        left_bytes = left_bytes;
      }
    
    let parse len s =
      let md4 = get_md4 s 1 in
      let ip = get_ip s 17 in
      let port = get_port s 21 in
      let tags, pos = get_tags s 23 names_of_tag in
      let server_info =  Some (get_ip s pos, get_port s (pos+4)) in
      let left_bytes = String.sub s (pos+6) (String.length s - pos - 6) in
      {
        md4 = md4;
        ip = ip;
        port = port;
        tags = tags;
        server_info = server_info;
        left_bytes = left_bytes;
        version = -1;
      }
    
    let print t = 
      lprintf "Connect reply from [%s:%d] MD4: %s"
        (Ip.to_string t.ip)
	t.port
        (Md4.to_string t.md4);
      (match t.server_info with
          None -> lprintf_nl ""
        | Some (ip, port) ->
            lprintf_nl " on server: %s:%d" (Ip.to_string ip) port);
      lprintf "tags: ";
      print_tags t.tags;
      if String.length t.left_bytes <> 0 then begin
        lprintf "  left bytes = ";
        String.iter (fun c -> lprintf "(%d)" (int_of_char c))
        t.left_bytes  end
      
    let write buf t =
      buf_md4 buf t.md4;
      buf_ip buf t.ip;
      buf_port buf t.port;
      buf_tags buf t.tags names_of_tag;
      begin
        match t.server_info with
          None -> ()
        | Some (ip, port) ->
            buf_ip buf ip;
            buf_port buf port;
      end;
      Buffer.add_string buf t.left_bytes
  end

module Say = struct
    type t = string
      
    let parse len s =
      let (s, p) = get_string s 1 in
      s
      
    let print t =
      lprintf "SAY %s" t
      
    let write buf t =
      buf_string buf t
  end
  
module OneMd4 = functor(M: sig val m : string end) -> (struct 
    type t = Md4.t
      
    let parse len s = 
      get_md4 s 1
      
    let print t = 
          lprintf "%s OF %s" M.m (Md4.to_string t)
          
    let write buf t = 
      buf_md4 buf t
      end)
  
module JoinQueue = struct
    type t = Md4.t option
      
    let parse len s = 
      if len >= 17 then
        Some (get_md4 s 1)
      else None
      
    let print t = 
      lprintf "JOIN QUEUE";
      (match t with None -> () | Some md4 ->
            lprintf " OF %s" (Md4.to_string md4));
      lprintf_nl ""
          
    let write emule buf t = 
      if extendedrequest emule > 0 then
        match t with
          None -> ()
        | Some md4 ->
            buf_md4 buf md4
  end
    (*
      : sig
        type t
          val parse : int -> string  -> t
          val print : t -> unit
          val write : Buffer.t -> t  -> unit
          val t :t 
          end
      )
*)
    
(* In Emule, this message contains much more information, and will probably
remove the need for QueryChunks. *)

let get_bitmap s pos =
  let nchunks = get_int16 s pos in
  let chunks, pos = 
    if nchunks = 0 then [||], pos+2 else
    let pos = pos + 2 in
    let chunks = Array.create nchunks false  in
    for i = 0 to (nchunks-1) / 8 do
      let m = get_uint8 s (pos + i) in
      for j = 0 to 7 do
        let n = i * 8 + j in
        if n < nchunks then
          chunks.(n) <- (m land (1 lsl j)) <> 0;
      done;
    done;
    let pos = pos + (nchunks-1)/8 + 1 in
    chunks, pos
  in
  chunks, pos

let print_bitmap chunks =
  lprint_string "\n   ";
  Array.iter (fun b -> 
      if b then lprintf "1" else lprintf "0") chunks

let write_bitmap buf chunks =
  let nchunks = Array.length chunks in
  buf_int16 buf nchunks;
  if nchunks > 0 then 
  for i = 0 to (nchunks-1) / 8 do
    let m = ref 0 in
    for j = 0 to 7 do
      let n = i * 8 + j in
      if n < nchunks then
        if chunks.(n) then
          m :=  !m lor (1 lsl j);
    done;
    buf_int8 buf !m
  done
  
module QueryFile  = struct
    type t = {
        md4 : Md4.t;
        emule_extension : (bool array * int) option;
      }
    
    let parse emule len s = 
(*      Printf.printf "Query File: emule version %d len %d" 
      (extendedrequest emule) len;
      print_newline (); *)
      let md4 = get_md4 s 1 in
      let emule_extension = 
        try
          if len < 18 || extendedrequest emule = 0 then None else
          let chunks, pos = get_bitmap s 17 in
          let ncompletesources = 
            if extendedrequest emule > 1 && len > pos+1 then get_int16 s pos
            else -1 in
          Some (chunks, ncompletesources)
        with _ -> None
      in
      { md4 = md4; 
        emule_extension = emule_extension }
    
    
    let print t = 
      lprintf "QUERY FILE OF %s" (Md4.to_string t.md4);
      match t.emule_extension with
        None -> ()
      | Some (bitmap, ncompletesources) ->
          print_bitmap bitmap; 
          lprintf_nl "";
          if ncompletesources >= 0 then
            lprintf_nl "Complete sources: %d" ncompletesources
    
    let write emule buf t = 
      buf_md4 buf t.md4;
      match t.emule_extension with
        None -> ()
      | Some (chunks, ncompletesources) ->
          if extendedrequest emule > 0 then begin
              write_bitmap buf chunks;
              if extendedrequest emule > 1 && ncompletesources >= 0 then
                buf_int16 buf ncompletesources
            end
            
  end
  
  
module QueryChunks  = OneMd4(struct let m = "QUERY CHUNKS" end)
  (* Request 79 *)
    
module QueryChunkMd4  = OneMd4(struct let m = "QUERY CHUNKS MD4" end)
module EndOfDownload  = OneMd4(struct let m = "END OF DOWNLOAD MD4" end)
module NoSuchFile  = OneMd4(struct let m = "NO SUCH FILE" end)

module QueryChunksReply = struct (* Request 80 *)
    
    type t = {
        md4 : Md4.t;
        chunks: bool array;
      }
    
    let parse len s = 
      let md4 = get_md4 s 1 in
      let chunks, pos = get_bitmap s 17 in
      {
        md4 = md4;
        chunks = chunks;
      }
      
    let print t =
      lprintf_nl "CHUNKS for %s" (Md4.to_string t.md4);
      lprint_string "   ";
      Array.iter (fun b -> 
          if b then lprintf "1" else lprintf "0") t.chunks;
      lprintf_nl ""
    
    let write buf t =
      buf_md4 buf t.md4;
      write_bitmap buf t.chunks;
      if t.chunks = [||] then buf_int8 buf 0
                
  end
(*
dec: [(96)(215)(1)(0)(0)(0)(0)(0)(0)(0)(0)(0)(0)]

OP_QUEUERANKING: int16
  
  
*)


module QueryChunkMd4Reply = struct (* Request 80 *)
    
    type t = {
        md4 : Md4.t;
        chunks: Md4.t array;
      }
      
    let parse len s = 
      let md4 = get_md4 s 1 in
      let nchunks = get_int16 s 17 in
(*      lprintf "nchunks : %d" nchunks; lprint_newline (); *)
      let chunks = Array.create nchunks md4  in
      for i = 0 to nchunks - 1 do
        chunks.(i) <- get_md4 s (19 + i * 16)        
      done;
      {
        md4 = md4;
        chunks = chunks;
      }

    let print t =
      lprintf_nl "CHUNKS for %s" (Md4.to_string t.md4);
      lprint_string "   ";
      Array.iter (fun b -> 
          lprintf "  %s" (Md4.to_string b))
      t.chunks;
      lprintf_nl ""
      
    let write buf t =
      buf_md4 buf t.md4;
      let nchunks = Array.length t.chunks in
      buf_int16 buf nchunks;
      for i = 0 to nchunks - 1 do
        buf_md4 buf t.chunks.(i)
      done
      
  end
  
module QueryFileReply  = struct 
    type t = {
        md4 : Md4.t;
        name : string;
      }
      
    let parse len s = 
      let name, _ = get_string s 17 in
      { md4 = get_md4 s 1;
        name =  name;
      }
      
    let print t = 
      lprintf_nl "QUERY FILE REPLY OF %s" (Md4.to_string t.md4);
      lprintf_nl "  name = \"%s\"" t.name
      
    let write buf t = 
      buf_md4 buf t.md4;
      buf_string buf t.name
  end
    
module Bloc  = struct 
    type t = {
        md4 : Md4.t;
        start_pos : int64;
        end_pos: int64;
        bloc_str: string;
        bloc_begin : int;
        bloc_len : int;
      }
      
    let parse len s = 
      {
        md4 = get_md4 s 1;
        start_pos = get_uint64_32 s 17;
        end_pos = get_uint64_32 s 21;
        bloc_str = s;
        bloc_begin = 25;
        bloc_len = len - 25;
      }
      
    let print t = 
      lprintf "BLOC OF %s len %Ld [%Ld - %Ld] " (Md4.to_string t.md4)
      (t.end_pos -- t.start_pos)
      t.start_pos
        t.end_pos
      
    let write buf t = 
      buf_md4 buf t.md4;
      buf_int64_32 buf t.start_pos;
      buf_int64_32 buf t.end_pos;
      Buffer.add_substring buf t.bloc_str t.bloc_begin t.bloc_len
  end
    
module QueryBloc  = struct 
    type t = {
        md4 : Md4.t;
        start_pos1 : int64; (* 180 ko *)
        end_pos1: int64;
        start_pos2 : int64;
        end_pos2: int64;
        start_pos3 : int64;
        end_pos3: int64;
      }
      
    let parse len s = 
      {
        md4 = get_md4 s 1;
        start_pos1 = get_uint64_32 s 17;
        end_pos1 = get_uint64_32 s 29;
        start_pos2 = get_uint64_32 s 21;
        end_pos2 = get_uint64_32 s 33;
        start_pos3 = get_uint64_32 s 25;
        end_pos3 = get_uint64_32 s 37;
      }
      
    let print t = 
      lprintf "QUERY BLOCS OF %s [%s - %s] [%s - %s] [%s - %s]"
      (Md4.to_string t.md4)
      (Int64.to_string t.start_pos1) (Int64.to_string t.end_pos1)
      (Int64.to_string t.start_pos2) (Int64.to_string t.end_pos2)
      (Int64.to_string t.start_pos3) (Int64.to_string t.end_pos3)
      
    let write buf t = 
      buf_md4 buf t.md4;
      buf_int64_32 buf t.start_pos1;
      buf_int64_32 buf t.start_pos2;
      buf_int64_32 buf t.start_pos3;
      buf_int64_32 buf t.end_pos1;
      buf_int64_32 buf t.end_pos2;
      buf_int64_32 buf t.end_pos3
      
  end

  
let unit = ()
module NoArg = functor(M: sig val m : string end) -> (struct 
        type t = unit
        
        let parse len s = ()
        
        let print t = 
          lprintf_nl "%s:" M.m
        
        let write (buf: Buffer.t) (t: t) = unit
          
        let t = (() : t)
      end : sig
        type t
          val parse : int -> string  -> t
          val print : t -> unit
          val write : Buffer.t -> t  -> unit
          val t :t 
          end
      )
    
module AvailableSlot = NoArg(struct let m = "AvailableSlot" end)
module ReleaseSlot = NoArg(struct let m = "ReleaseSlot" end)
module CloseSlot = NoArg(struct let m = "CloseSlot" end)
module ViewFiles = NoArg(struct let m = "VIEW FILES" end)

  
module ViewFilesReply = struct 
    
    type file = {
        md4: Md4.t;
        ip: Ip.t;
        port: int;
        tags:  tag list;
      }
    
    type t = tagged_file list
    
    let names_of_tag = file_common_tags
    
    let rec get_files  s pos n =
      if n = 0 then [], pos else
      let md4 = get_md4 s pos in
      let ip = get_ip s (pos + 16) in
      let port = get_port s (pos + 20) in
      let tags, pos = get_tags s (pos+22) names_of_tag in
      let file = {
          f_md4 = md4;
          f_ip = ip;
          f_port = port;
          f_tags = tags;
        } in
      let files, pos =  get_files s pos (n-1) in
      file :: files, pos
    
    
    let parse len s =
      let n = get_int s 1 in
      let files, pos = get_files s 5 n in
      files
    
    let print t = 
      lprintf_nl "VIEW FILES REPLY:";
      List.iter (fun t ->
          lprintf_nl "FILE:";
          lprintf_nl "  MD4: %s" (Md4.to_string t.f_md4);
          lprintf_nl "  ip: %s" (Ip.to_string t.f_ip);
          lprintf_nl "  port: %d" t.f_port;
          lprintf "  tags: ";
          print_tags t.f_tags;
          lprintf_nl "";) t
    
    let rec write_files buf files =
      match files with
        [] -> ()
      | file :: files ->
          buf_md4 buf file.f_md4;
          buf_ip buf file.f_ip;
          buf_port buf file.f_port;
          buf_tags buf file.f_tags names_of_tag;
          write_files buf files
    
    let write buf t = 
      buf_int buf (List.length t);
      write_files buf t
        
    let rec write_files_max buf files nfiles max_len =
      let prev_len = Buffer.length buf in
      match files with
        [] -> nfiles, prev_len
      | file :: files ->
          buf_md4 buf file.f_md4;
          buf_ip buf file.f_ip;
          buf_port buf file.f_port;
          buf_tags buf file.f_tags names_of_tag;
          if Buffer.length buf < max_len then
            write_files_max buf files (nfiles+1) max_len
          else
            nfiles, prev_len

  end
  
module OtherLocations = struct 

    type t = Ip.t list
      
    let parse len s =
      let list = ref [] in
      for i = 0 to len / 4 - 1 do
        list := (get_ip s (i*4+1)) :: !list;
      done;
      !list
    
    let print t = 
      lprintf_nl "OTHER LOCATIONS:\n";
      List.iter (fun ip ->
          lprintf_nl "  ip: %s" (Ip.to_string ip);) t
        
    let write buf t = 
      List.iter (buf_ip buf) t
  end
  
module NewUserID = struct 

    type t = Ip.t * Ip.t
      
    let parse len s =
      get_ip s 1, get_ip s 5
    
    let print (ip1,ip2) = 
      lprintf_nl "NEW USER ID: %s -> %s" (Ip.to_string ip1)
      (Ip.to_string ip2)
        
    let write buf (ip1,ip2) = 
      buf_ip buf ip1;
      buf_ip buf ip2
  end


module Sources = struct 

    type t = {
        md4: Md4.t;
        sources : (Ip.t * int * Ip.t) list;
      }
      
    let parse len s =
      let len = get_int16 s 1 in
      let md4 = get_md4 s 3 in
      let list = ref [] in
      let pos = 19 in
      for i = 0 to len - 1 do
        list := (get_ip s (19 + 10 * i), get_port s (23 + 10 * i),
          get_ip  s (25 + 10 * i)) :: !list;
      done;
      { md4 = md4;
        sources = !list;
      }
    
    let print t = 
      lprintf_nl "SOURCES for %s:" (Md4.to_string t.md4);
      List.iter (fun (ip1, port, ip2) ->
          lprintf_nl "  %s:%d:%s" (Ip.to_string ip1) port(Ip.to_string ip2)) t.sources
        
    let write buf t = 
      buf_int16 buf (List.length t.sources);
      buf_md4 buf t.md4;
      List.iter (fun (ip1, port, ip2) -> 
          buf_ip buf ip1;
          buf_port buf port;
          buf_ip buf ip2) t.sources
  end
  

      
module EmuleClientInfo = struct 

    type t = {
        version : int; (* CURRENT_VERSION_SHORT = !!emule_protocol_version *)
        protversion : int; (* EMULE_PROTOCOL_VERSION = 0x1 *)
        mutable tags : tag list;
      }
      
    let names_of_tag =
      [
        "\032", "compression";
        "\033", "udpport";
        "\034", "udpver";
        "\035", "sourceexchange";
        "\036", "comments";
        "\037", "extendedrequest";
        "\038", "compatibleclient";
        "\039", "features";
        "\060", "downloadtime";
        "\061", "incompleteparts";
        "\062", "l2hac";
        "\065", "mod_unknown41";
        "\066", "mod_unknown42";
        "\067", "mod_unknown43";
        "\084", "mod_featureset";
        "\086", "mod_protocol";
        "\085", "mod_version";
        "\090", "mod_bowlfish";
        "\092", "mod_secure_community";
        "\102", "mod_fusion";
        "\103", "mod_fusion_version";
        "\119", "mod_tarod";
        "\120", "mod_tarod_version";
        "\121", "mod_morph";
        "\128", "mod_morph_version";
        "\130", "mod_mortillo";
        "\131", "mod_mortillo_version";
        "\132", "chanblard_version";
        "\133", "signature";
        "\134", "cache";
        "\135", "mod_lsd";
        "\136", "mod_lsd_version";
        "\144", "mod_lovelace_version";
        "\148", "mod_oxy";
        "\153", "mod_plus";
        "\160", "mod_wombat";
        "\161", "dev_wombat";
      ]

    let names_of_tag = 
      List.map (fun (v, name) -> (v, Field_UNKNOWN name)) names_of_tag
      
    let parse len s =
      let version = get_uint8 s 1 in
      let protversion = get_uint8 s 2 in
      let tags,_ = get_tags s 3 names_of_tag in
      {
        version = version; 
        protversion = protversion;
        tags = tags;
      }
      
    let print m t = 
      lprintf_nl "%s:" m;
      lprintf_nl "  version: %d" t.version;
      lprintf_nl "  protversion: %d" t.version;
      lprintf "  tags: "; 
      print_tags t.tags;
      lprintf_nl ""
        
    let write buf t = 
      buf_int8 buf t.version;
      buf_int8 buf t.protversion;
      buf_tags buf t.tags names_of_tag;
      
  end
      
module EmuleQueueRanking = struct 

    type t = int
      
    let parse len s = get_int16 s 1      
    let print t = 
      lprintf_nl "QUEUE RANKING: %d" t

    let string_null10 = String.make 10 (char_of_int 0)
      
    let write buf t = 
      buf_int16 buf t;
      Buffer.add_string buf string_null10
            
  end

module QueueRank = struct 

    type t = int
      
    let parse len s = get_int s 1      
    let print t = 
      lprintf_nl "QUEUE RANK: %d" t

    let write buf t = 
      buf_int buf t
            
  end
      
module EmuleRequestSources = struct 

    type t =  Md4.t
      
    let parse len s = 
      get_md4 s 1
      
    let print t = 
      lprintf_nl "EMULE REQUEST SOURCES: %s" (Md4.to_string t)

    let write buf t = 
      buf_md4 buf t 
            
  end
      
module EmuleRequestSourcesReply = struct 
    
    type source = {
        src_ip : Ip.t;
        src_port : int;
        mutable src_server_ip : Ip.t;
        mutable src_server_port : int;
        mutable src_md4 : Md4.t;
      }
    
    type t = {
        md4 : Md4.t;
        sources : source array;        
      }
    
    let dummy_source = {
        src_ip = Ip.null;
        src_port = 0;
        src_server_ip = Ip.null;
        src_server_port = 0;
        src_md4 = Md4.null;
      }
    
    let parse e len s = 
      let md4 = get_md4 s 1 in
      let ncount = get_int16 s 17 in
      
      let sources = 
        if ncount = 0 then [||] else
        let slen = (len - 19) / ncount in
(*        lprintf "PER SOURCES LEN: %d\n" slen; *)
        let sources = Array.create ncount dummy_source in
        let rec iter pos i =
          if i < ncount then 
            let ss = {
                dummy_source with
                src_ip = get_ip s pos;
                src_port = get_int16 s (pos+4);
              } in
            let pos =
              if slen > 6 then begin
                  ss.src_server_ip <- get_ip s (pos+6);
                  ss.src_server_port <- get_int16 s (pos+10);
                  if slen > 12 && (sourceexchange e > 1) then begin
                      ss.src_md4 <- get_md4 s (pos+12);
                      pos + 28
                    end else
                    pos + 12
                end
              else pos + 6 
            in
            sources.(i) <- ss;
            iter pos (i+1)
        in
        iter 19 0;
        sources
      in
      {
        md4 = md4;
        sources = sources;
      }
        
    let print t = 
      let ncount = Array.length t.sources in
      lprintf_nl "EMULE SOURCES REPLY: %d sources for %s" 
        ncount (Md4.to_string t.md4); 
       for i = 0 to ncount - 1 do
        let s = t.sources.(i) in
          if Ip.valid s.src_ip then
            lprintf_nl "  %s:%d" (Ip.to_string s.src_ip) s.src_port
          else 
            lprintf_nl "  Indirect from %s:%d"
              (Ip.to_string s.src_server_ip) s.src_server_port;
          if s.src_md4 != Md4.null then
            lprintf_nl "   Md4: %s" (Md4.to_string s.src_md4)
      done

    let write e buf t = 
      buf_md4 buf t.md4;
      let ncount = Array.length t.sources in
      buf_int16 buf ncount;
      
      for i = 0 to ncount - 1 do
        let s = t.sources.(i) in
          buf_ip buf s.src_ip;
          buf_port buf s.src_port; 
          if sourceexchange e > 0 then begin
              buf_ip buf s.src_server_ip;
              buf_port buf s.src_server_port; 
              if sourceexchange e > 1 then
                buf_md4 buf s.src_md4
            end
      done
            
  end

  
type t = 
| ConnectReq of Connect.t
| ConnectReplyReq of ConnectReply.t
| QueryFileReq of QueryFile.t
| QueryFileReplyReq of QueryFileReply.t
| BlocReq of Bloc.t
| QueryBlocReq of QueryBloc.t
| JoinQueueReq of JoinQueue.t (* sent before queryBloc *)
| AvailableSlotReq of AvailableSlot.t
| ReleaseSlotReq of ReleaseSlot.t
| CloseSlotReq of CloseSlot.t
| QueryChunksReq of QueryChunks.t
| QueryChunksReplyReq of QueryChunksReply.t
| QueryChunkMd4Req of QueryChunkMd4.t
| QueryChunkMd4ReplyReq of QueryChunkMd4Reply.t
| ViewFilesReq of ViewFiles.t
| ViewFilesReplyReq of ViewFilesReply.t
| QueueReq of OtherLocations.t
| UnknownReq of int * string
| OtherLocationsReq of OtherLocations.t
| SayReq of Say.t
| SourcesReq of Sources.t
| EndOfDownloadReq of EndOfDownload.t
| NewUserIDReq of NewUserID.t
| NoSuchFileReq of NoSuchFile.t  
| QueueRankReq of QueueRank.t
  
  
| EmuleClientInfoReq of EmuleClientInfo.t
| EmuleClientInfoReplyReq of EmuleClientInfo.t
| EmuleQueueRankingReq of EmuleQueueRanking.t
| EmuleRequestSourcesReq of EmuleRequestSources.t
| EmuleRequestSourcesReplyReq of EmuleRequestSourcesReply.t
| EmuleFileDescReq of string
| EmulePublicKeyReq of string
| EmuleSignatureReq of string
| EmuleSecIdentStateReq  of int * int64
| EmuleMultiPacketReq of Md4.t * t list
| EmuleMultiPacketAnswerReq of Md4.t * t list
| EmuleCompressedPart of Md4.t * int64 * int64 * string
  
let rec print t =
  begin
    match t with
    | ConnectReq t -> Connect.print t
    | ConnectReplyReq t -> ConnectReply.print t
    | QueryFileReq t -> QueryFile.print t
    | QueryFileReplyReq t -> QueryFileReply.print t
    | BlocReq t -> Bloc.print t
    | QueryBlocReq t -> QueryBloc.print t
    | JoinQueueReq t -> JoinQueue.print t
    | AvailableSlotReq t -> AvailableSlot.print t
    | ReleaseSlotReq t -> ReleaseSlot.print t
    | CloseSlotReq t -> CloseSlot.print t    
    | QueryChunksReq t -> QueryChunks.print t    
    | QueryChunksReplyReq t -> QueryChunksReply.print t    
    | QueryChunkMd4Req t -> QueryChunkMd4.print t    
    | QueryChunkMd4ReplyReq t -> QueryChunkMd4Reply.print t    
    | ViewFilesReplyReq t -> ViewFilesReply.print t
    | ViewFilesReq t -> ViewFiles.print t    
    | QueueReq t -> OtherLocations.print t    
    | OtherLocationsReq t  -> OtherLocations.print t
    | SayReq t -> Say.print t
    | SourcesReq t -> Sources.print t
    | EndOfDownloadReq t -> EndOfDownload.print t
    | NewUserIDReq t -> NewUserID.print t
    | NoSuchFileReq t -> NoSuchFile.print t
    | QueueRankReq t -> 
        QueueRank.print t
    
    | EmuleClientInfoReq t -> 
        EmuleClientInfo.print "EMULE CLIENT INFO"  t
    | EmuleClientInfoReplyReq t -> 
        EmuleClientInfo.print "EMULE CLIENT INFO REPLY" t
    | EmuleQueueRankingReq t -> 
        EmuleQueueRanking.print t
    | EmuleRequestSourcesReq t -> 
        EmuleRequestSources.print  t
    | EmuleRequestSourcesReplyReq t -> 
        EmuleRequestSourcesReply.print t

    | EmuleFileDescReq t -> 
        lprintf "EMULE FILE DESC %s" t

    | EmuleMultiPacketReq (md4, list) ->
        lprintf_nl "EmuleMultiPacket for %s:" (Md4.to_string md4);
        List.iter (fun t ->
            lprintf "  ";
            print t
        ) list
        
    | EmuleMultiPacketAnswerReq (md4, list) ->
        lprintf_nl "EmuleMultiPacketAnswer for %s:" (Md4.to_string md4);
        List.iter (fun t ->
            lprintf "  ";
            print t
        ) list
    | EmuleSecIdentStateReq (int, int64) ->
        lprintf_nl "EmuleSecIdentState for %d, %Ld" int int64
    | EmuleSignatureReq s -> 
        lprintf_nl "EmuleSignature %s" (String.escaped s)
    | EmulePublicKeyReq s ->
        lprintf_nl "EmulePublicKey %s" (String.escaped s)

    | EmuleCompressedPart (md4, statpos, newsize, bloc) ->
        lprintf_nl "EmuleCompressedPart for %s %Ld %Ld len %d"
          (Md4.to_string md4) statpos newsize (String.length bloc)
        
    | UnknownReq (opcode, s) ->  
        let len = String.length s in
        lprintf_nl "UnknownReq: magic %d, opcode %d\n   len %d" opcode 
        (int_of_char s.[0])
        (String.length s);
        lprintf "ascii: [";
        for i = 0 to len - 1 do
          let c = s.[i] in
          let n = int_of_char c in
          if n > 31 && n < 127 then
            lprintf " %c" c
          else
            lprintf "(%d)" n
        done;
        lprintf_nl "]";
        lprintf "dec: [";
        for i = 0 to len - 1 do
          let c = s.[i] in
          let n = int_of_char c in
          lprintf "(%d)" n            
        done;
        lprintf_nl "]"
  end

  
let rec parse_emule_packet emule opcode len s =
(*
  lprintf "Emule magic: %d opcode %d:" magic opcode; lprint_newline ();
          dump s; lprint_newline ();
  *)        
  let t = match opcode with
    | 1 -> EmuleClientInfoReq (EmuleClientInfo.parse len s)
    | 2 -> EmuleClientInfoReplyReq (EmuleClientInfo.parse len s)
    
    
    
    | 0x60 (* 96 *) -> EmuleQueueRankingReq (EmuleQueueRanking.parse len s)
    
    | 0x61 (* 97 *) -> 
        let (comment,_) = get_string s 1 in
        EmuleFileDescReq comment
    
    | 0x81 (* 129 *) -> EmuleRequestSourcesReq (EmuleRequestSources.parse len s)
    | 0x82 (* 130 *) -> 
        EmuleRequestSourcesReplyReq (
          EmuleRequestSourcesReply.parse emule len s)
    
    | 0x40 (* 64 *) ->
(* OP_COMPRESSEDPART *)
        let md4 = get_md4 s 1 in
        let statpos = get_uint64_32 s 17 in
        let newsize = get_uint64_32 s 21 in
        let bloc = String.sub s 25 (len-25) in
        EmuleCompressedPart (md4, statpos, newsize, bloc)
    
    | 0x85 (* 133 *) -> 
        let len = get_uint8 s 1 in
        let key = String.sub s 2 len in
        EmulePublicKeyReq key
    
    | 0x86 (* 134 *) -> 
        let len = get_uint8 s 1 in
        let signature = String.sub s 2 len in
        EmuleSignatureReq  signature
    
    | 0x87 (* 135 *) -> 
        let state = get_uint8 s 1 in
        let challenge = get_uint64_32 s 2 in
        EmuleSecIdentStateReq (state, challenge)

(*     | 0x90 (* 144 *) -> RequestPreview *)
(*    | 0x91 (* 145 *) -> PreviewAnswer *)
    | 0x92 (* 146 *) -> 
        let md4 = get_md4 s 1 in
        
(*        Printf.printf "MULTI EMULE VERSION %d" 
          (extendedrequest emule); print_newline (); *)
        let pos = 17 in
        let rec iter pos =
          if pos < len then
            let opcode = get_uint8 s pos in
            match opcode with
              0x58 (* 88 *) -> 
                let bitmap, pos = get_bitmap s (pos+1) in
                let ncompletesources, pos = 
                  if extendedrequest emule > 1 then 
                    get_int16 s pos, pos+2
                  else -1, pos
                in
                (QueryFileReq {
                    QueryFile.md4 = md4;
                    QueryFile.emule_extension = Some (bitmap, ncompletesources);
                  }) :: (iter pos)
            | 0x4F (* 79 *) -> 
                (QueryChunksReq md4) :: iter (pos+1)
            | 0x81 (* 129 *) -> 
                (EmuleRequestSourcesReq md4) :: iter (pos+1)
            | _ ->
                lprintf_nl "Unknown short emule packet %d" opcode;
                raise Not_found
          else
            []
        in
        EmuleMultiPacketReq (md4, iter 17)
    
    | 0x93 (* 147 *) -> 
        let md4 = get_md4 s 1 in
        
(*        Printf.printf "MULTI EMULE VERSION %d" 
          (extendedrequest emule); print_newline (); *)
        let rec iter s pos len =
          if pos < len then
            let opcode = get_uint8 s pos in
            match opcode with
            | 89 -> 
                let module Q = QueryFileReply in
                let name, pos = get_string s (pos+1) in
                let q = { 
                    Q.md4 = md4;
                    Q.name =  name;
                  } in
                (QueryFileReplyReq q) :: (iter s pos len)
            | 80 ->
                let module Q = QueryChunksReply in
                let chunks, pos = get_bitmap s (pos+1) in
                let q = {
                    Q.md4 = md4;
                    Q.chunks = chunks;
                  } in
                (QueryChunksReplyReq q) :: (iter s pos len)
            | _ ->
                lprintf_nl "Unknown packet in emule multipacket 0x93: %d" opcode;
                raise Not_found
          else
            []
        in
        EmuleMultiPacketAnswerReq (md4, iter s 17 len)
    
    | code -> 
(*        Printf.printf "UNKNOWN EMULE MESSAGE %d" code; print_newline ();*)
        raise Not_found
  in
(*
          lprintf "EMULE MESSAGE: "; lprint_newline ();
          print t;
          lprint_newline (); *)
  t

and parse emule_version magic s =
  try 
    let len = String.length s in
    if len = 0 then raise Not_found;
    let opcode = int_of_char (s.[0]) in
(*lprintf "opcode: %d" opcode; lprint_newline (); *)
    match magic with
      227 ->
        begin
          match opcode with 
          | 1 -> ConnectReq (Connect.parse len s)
          | 70 -> BlocReq (Bloc.parse len s)
          | 71 -> QueryBlocReq (QueryBloc.parse len s)
          | 72 -> NoSuchFileReq (NoSuchFile.parse len s)
          | 73 -> EndOfDownloadReq (EndOfDownload.parse len s)
          | 74 -> ViewFilesReq (ViewFiles.parse len s)
          | 75 -> ViewFilesReplyReq (ViewFilesReply.parse len s)
          | 76 -> ConnectReplyReq (ConnectReply.parse len s)
          | 77 -> NewUserIDReq (NewUserID.parse len s)
          | 78 -> SayReq (Say.parse len s)
          | 79 -> QueryChunksReq (QueryChunks.parse len s)
          | 80 -> QueryChunksReplyReq (QueryChunksReply.parse len s)
          | 81 -> QueryChunkMd4Req (QueryChunkMd4.parse len s)
          | 82 -> QueryChunkMd4ReplyReq (QueryChunkMd4Reply.parse len s)
(* JoinQueue: the sender wants to join the upload queue *)
          | 84 -> JoinQueueReq (JoinQueue.parse len s) 
(* AvailableSlot: there is an available slot in upload queue *)
          | 85 -> AvailableSlotReq (AvailableSlot.parse len s)
(* ReleaseSlot: the upload is finished *)
          | 86 -> ReleaseSlotReq (ReleaseSlot.parse len s)
(* CloseSlot: the upload slot is not available *)
          | 87 -> CloseSlotReq (CloseSlot.parse len s)
          | 88 -> QueryFileReq (QueryFile.parse emule_version len s)
          | 89 -> QueryFileReplyReq (QueryFileReply.parse len s)
          | 92 -> QueueRankReq (QueueRank.parse len s)
          | 250 -> SourcesReq (Sources.parse len s)        
          
          | _ -> raise Not_found
        end 
    
    | 0xc5  -> (* 197: emule extended protocol *)
        parse_emule_packet emule_version opcode len s

(* Compressed packet, probably sent by cDonkey ? *)
    
    | 0xD4 -> (* 212 *)
        
        if Autoconf.has_zlib then
          let s = Autoconf.zlib__uncompress_string2 (String.sub s 1 (len-1)) in
          let s = Printf.sprintf "%c%s" (char_of_int opcode) s in
          try
            parse_emule_packet emule_version opcode (String.length s) s
          with
          | e -> 
              if !CommonOptions.verbose_unknown_messages then begin
                  lprintf_nl "Unknown message From client: %s (magic %d)"
                    (Printexc2.to_string e) magic;
                  let tmp_file = Filename.temp_file "comp" "pak" in
                  File.from_string tmp_file s;
                  lprintf_nl "Saved unknown packet %s" tmp_file;
                  dump s;
                  lprintf_nl "";
                end;
              UnknownReq (magic,s)
              
        else
          failwith "No Zlib to uncompress packet"
        (*
        lprintf "Compressed message decompressed with opcode %d" opcode; lprint_newline ();
        if !CommonOptions.verbose_unknown_messages then begin       
            let tmp_file = Filename.temp_file "comp" "unpak" in
            File.from_string tmp_file s;
            lprintf "Saved compressed packet %s" tmp_file; lprint_newline ();
          end;	   
        UnknownReq s        *)
    | _ -> 
        if !CommonOptions.verbose_unknown_messages then
            lprintf_nl "Strange magic: %d" magic;
        raise Not_found
  with
  | e -> 
      if !CommonOptions.verbose_unknown_messages then begin
          lprintf_nl "Unknown message From client: %s (magic %d)"
              (Printexc2.to_string e) magic;
	      	     let tmp_file = Filename.temp_file "comp" "pak" in
	     File.from_string tmp_file s;
	     lprintf_nl "Saved unknown packet %s" tmp_file;

          dump s;
          lprintf_nl "";
        end;
      UnknownReq (magic,s)
  
let write emule buf t =
  let magic = match t with
      EmuleMultiPacketAnswerReq _
    | EmuleMultiPacketReq _ 
    | EmuleSecIdentStateReq _ 
    | EmuleSignatureReq _
    | EmulePublicKeyReq _
    | EmuleRequestSourcesReplyReq _
    | EmuleRequestSourcesReq _ 
    | EmuleClientInfoReplyReq _
    | EmuleClientInfoReq _
    | EmuleFileDescReq _
    | EmuleQueueRankingReq _
    | EmuleCompressedPart _
      -> 0xC5
    | _ 
      ->  227
  in
  begin
    match t with
    | ConnectReq t -> 
        buf_int8 buf 1;
        Connect.write buf t
    | ConnectReplyReq t -> 
        buf_int8 buf 76;
        ConnectReply.write buf t
    | QueryFileReq t -> 
        buf_int8 buf 88;
        QueryFile.write emule buf t
    | QueryFileReplyReq t -> 
        buf_int8 buf 89;
        QueryFileReply.write buf t
    | QueueReq t ->
        buf_int8 buf 77;
        OtherLocations.write buf t
    | QueryBlocReq t ->
        buf_int8 buf 71;
        QueryBloc.write buf t
    | BlocReq t -> 
        buf_int8 buf 70;
        Bloc.write buf t
    | JoinQueueReq t -> 
        buf_int8 buf 84;
        JoinQueue.write emule buf t
    | QueryChunksReq t -> 
        buf_int8 buf 79;
        QueryChunks.write buf t
    | QueryChunksReplyReq t -> 
        buf_int8 buf 80;
        QueryChunksReply.write buf t
    | QueryChunkMd4Req t -> 
        buf_int8 buf 81;
        QueryChunkMd4.write buf t
    | QueryChunkMd4ReplyReq t -> 
        buf_int8 buf 82;
        QueryChunkMd4Reply.write buf t
    | AvailableSlotReq t -> 
        buf_int8 buf 85;
        AvailableSlot.write buf t
    | ReleaseSlotReq t -> 
        buf_int8 buf 86;
        ReleaseSlot.write buf t
    | CloseSlotReq t -> 
        buf_int8 buf 87;
        CloseSlot.write buf t
    | ViewFilesReq t -> 
        buf_int8 buf 74;
        ViewFiles.write buf t
    | ViewFilesReplyReq t -> 
        buf_int8 buf 75;
        ViewFilesReply.write buf t
    | OtherLocationsReq t ->
        buf_int8 buf 72;
        OtherLocations.write buf t
    | SayReq t ->
        buf_int8 buf 78;
        Say.write buf t
    | SourcesReq t ->
        buf_int8 buf 250;
        Sources.write buf t
    | NewUserIDReq t ->
        buf_int8 buf 77;
        NewUserID.write buf t
    | EndOfDownloadReq t ->
        buf_int8 buf 73;
        EndOfDownload.write buf t
    | NoSuchFileReq t ->
        buf_int8 buf 72;
        NoSuchFile.write buf t
    | QueueRankReq t ->
        buf_int8 buf 92;
        QueueRank.write buf t
    
    | EmuleClientInfoReq t ->
        buf_int8 buf 1;
        EmuleClientInfo.write buf t
    | EmuleClientInfoReplyReq t ->
        buf_int8 buf 2;
        EmuleClientInfo.write buf t
    | EmuleQueueRankingReq t ->
        buf_int8 buf 0x60;
        EmuleQueueRanking.write buf t
    | EmuleRequestSourcesReq t ->
        buf_int8 buf 0x81;
        EmuleRequestSources.write buf t
    | EmuleRequestSourcesReplyReq t ->
        buf_int8 buf 0x82;
        EmuleRequestSourcesReply.write emule buf t
    | EmuleFileDescReq t ->
        buf_int8 buf 0x61;
        buf_int8 buf 1;
        buf_string buf t

    | EmuleCompressedPart (md4, statpos, newsize, bloc) ->
        buf_int8 buf 0x40;
        buf_md4 buf md4;
        buf_int64_32 buf statpos;
        buf_int64_32 buf newsize;
        Buffer.add_string buf bloc
        
    | EmuleMultiPacketReq (md4, list) ->
        buf_int8 buf 0x92;
        buf_md4 buf md4;
        List.iter (fun t ->
            match t with
              QueryFileReq t ->
                buf_int8 buf 0x58;
                (match t.QueryFile.emule_extension with
                    None -> ()
                  | Some (bitmap, ncompletesources) ->
                      write_bitmap buf bitmap;
                      if ncompletesources >= 0 && extendedrequest emule > 1 then
                        buf_int16 buf ncompletesources)
            | QueryChunksReq _ ->
                buf_int8 buf 0x4F
            | EmuleRequestSourcesReq _ ->
                buf_int8 buf 0x81
            | _ -> 
                lprintf_nl "WARNING: Don't know how to write short packet:";
                print t;
                print_newline ();
        ) list
    
    | EmuleMultiPacketAnswerReq (md4, list) ->
        buf_int8 buf 0x93;
        buf_md4 buf md4;
        List.iter (fun t ->
            match t with
              QueryFileReplyReq t ->
                buf_int8 buf 89;
                buf_string buf t.QueryFileReply.name
            | QueryChunksReplyReq t ->
                buf_int8 buf 80;
                write_bitmap buf t.QueryChunksReply.chunks
            | _ -> 
                lprintf_nl "WARNING: Don't know how to write short packet:";
                print t;
                print_newline ();
        ) list
        
        
    | EmuleSecIdentStateReq (state,challenge) ->
        buf_int8 buf 0x87;
        buf_int8 buf state;
        buf_int64_32 buf challenge
        
    | EmuleSignatureReq s -> 
        buf_int8 buf 0x86;
        buf_int8 buf (String.length s);
        Buffer.add_string buf s
       
    | EmulePublicKeyReq s ->
        buf_int8 buf 0x85;
        buf_int8 buf (String.length s);
        Buffer.add_string buf s
        
    | UnknownReq (opcode, s) ->
        Buffer.add_string buf s
    
  end;
  magic 
  
(*


------------------------------------------------------
1044008574.297 192.168.0.3:37522 -> 80.26.114.12:13842 of len 6
? Become Friend ? ping ?

(227)(1)(0)(0)(0)
(98) 

------------------------------------------------------
1044008576.274 80.26.114.12:13842 -> 192.168.0.3:37522 of len 6
? OK ? pong ?

(227)(1)(0)(0)(0)(99)]

------------------------------------------------------
1044008687.977 192.168.0.3:37522 -> 80.26.114.12:13842 of len 6
Browse Main Dir
  
(227)(1)(0)(0)(0)
(93)

------------------------------------------------------
1044008690.832 80.26.114.12:13842 -> 192.168.0.3:37522 of len 43
Browse Main Dir Reply
(227)(38)(0)(0)(0)
(95)
(2)(0)(0)(0) --------> 2 directories:
(12)(0) C : \ D o w n l o a d s
(17)(0) ! I n c o m p l e t e   F i l e s


------------------------------------------------------
1044008766.137 192.168.0.3:37522 -> 80.26.114.12:13842 of len 20
Browse directory
  
(227)(15)(0)(0)(0)
(94)
(12)(0) C : \ D o w n l o a d s

------------------------------------------------------
1044008769.045 80.26.114.12:13842 -> 192.168.0.3:37522 of len 300
(227) p(8)(0)(0) `(12)(0) C : \ D o w n l o a d s(21)(0)(0)(0)(152) 2(229)(158)(218)(141)(217)(138) n(181) 6 ( ) h V(179)(0)(0)(0)(0)(0)(0)(3)(0)(0)(0)(2)(1)(0)(1)(11)(0) d e s k t o p . i n i(3)(1)(0)(2)(180)(0)(0)(0)(3)(1)(0)(19)(0)(0)(0)(0) y(16)(15) 9 O Z(219) i e(200)(10) |(29)(27) F(128)(0)(0)(0)(0)(0)(0)(5)(0)(0)(0)(2)(1)(0)(1)(15)(0) u t b o n u s p a c k . z i p(3)(1)(0)(2) J(16)(221)(0)(2)(1)(0)(3)(3)(0) P r o(2)(1)(0)(4)(3)(0) z i p(3)(1)(0)(19)(0)(0)(0)(0)(178)(145)(161)(146) P(199)(228)(249) K a :(9)(237)(246)(233) v(0)(0)(0)(0)(0)(0)(5)(0)(0)(0)(2)(1)(0)(1)(11)(0) c t f m a p s . z i p(3)(1)(0)(2)(236)(239)(23)(0)(2)(1)(0)(3)(3)(0) P r o(2)(1)(0)(4)(3)(0) z i p(3)(1)(0)(19)(0)(0)(0)(0) a n(251)(225) ^ g(205)(133)(25)(12) # ' J A(221) `(0)(0)(0)(0)(0)(0)(5)(0)(0)(0)(2)(1)(0)(1)(23)(0) u t i n o x x p a c k - n o - u m o d . z i p(3)(1)(0)(2)]
(227)(112)(8)(0)(0)
  
(96)
(12)(0) C : \ D o w n l o a d s
(21)(0)(0)(0) 21 files

(152)(50)(229)(158)(218)(141)(217)(138)(110)(181)(54)(40)(41)(104)(86)(179)
(0)(0)(0)(0)
(0)(0)
(3)(0)(0)(0)
(2)
(1)(0)(1)
(11)(0)  d e s k t o p . i n i
(3)
(1)(0)(2)
(180)(0)(0)(0)
(3)
(1)(0)(19)
(0)(0)(0)(0)

(121)(16)(15)(57)(79)(90)(219)(105)(101)(200)(10)(124)(29)(27)(70)(128)
(0)(0)(0)(0)
(0)(0)
(5)(0)(0)(0)
(2)
(1)(0)(1)
(15)(0) u t b o n u s p a c k . z i p
(3)
(1)(0)(2)
(74)(16)(221)(0)
(2)
(1)(0)(3)
(3)(0) Pro
(2)
(1)(0)(4)
(3)(0) zip
(3)
(1)(0)(19)
(0)(0)(0)(0)
....
  
*)
      
(* 92: Queue Rank *)
