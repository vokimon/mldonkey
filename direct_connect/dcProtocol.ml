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

open CommonGlobals
open DcGlobals
open DcTypes
open TcpBufferedSocket


module Empty = functor(M: sig val msg : string end) -> 
    struct
    
      let parse s = ()
      
      let print t =
        Printf.printf "message %s" M.msg
        
      let write buf t = ()
    end

module Empty2 = functor(M: sig val msg : string end) -> 
    struct
    
      let parse s = ()
      
      let print t =
        Printf.printf "message %s" M.msg
        
      let write buf t = Printf.bprintf buf "$%s" M.msg
    end

module SimpleNick =  functor(M: sig val msg : string end) -> 
    struct
    type t = string
      
      let parse nick = nick 
      
      let print t = 
        Printf.printf "%s [%s]" M.msg (String.escaped t) ;
        print_newline () 
      
      let write buf t = 
        Printf.bprintf buf " %s" t
    
  end

module SimpleNick2 =  functor(M: sig val msg : string end) -> 
    struct
    type t = string
      
      let parse nick = nick 
      
      let print t = 
        Printf.printf "%s [%s]" M.msg (String.escaped t) ;
        print_newline () 
      
      let write buf t = 
        Printf.bprintf buf "$%s %s" M.msg t
    
  end

module Lock = struct
    type t = {
        key : string;
        info : string;
      }
      
    let parse s = 
      match String2.splitn s ' ' 1 with
      | [key; info] -> { key = key; info = info }
      | _ -> assert false
      
    let print t = 
      Printf.printf "LOCK [%s] %s" (String.escaped t.key) 
      (String.escaped t.info);
      print_newline () 
      
    let write buf t = 
      Printf.bprintf buf " %s %s" t.key t.info
  end
  
module Direction = struct
    type t = {
        download : bool;
        level : int;
      }
      
    let parse s = 
      match String2.split s ' ' with
      | ["Download"; level] -> { download = true; level = int_of_string level }
      | ["Upload"; level] -> { download = true; level = int_of_string level }
      | _ -> assert false
      
    let print t = 
      Printf.printf "Direction %s %d" (
        if t.download then "Download" else "Upload") t.level;
      print_newline () 
      
    let write buf t = 
      Printf.bprintf buf "$Direction %s %d" (
        if t.download then "Download" else "Upload") t.level
    
  end
  
module Get = struct
    type t = {
        name : string;
        pos : int32;
      }
      
    let parse s = 
      let len = String.length s in
      let pos = String.rindex s '$' in
      {
        name = String.sub s 0 pos; 
        pos = Int32.of_string (String.sub s (pos+1) (len-pos-1));
      }
      
    let print t = 
      Printf.printf "Get [%s] %ld" (String.escaped t.name) 
      t.pos;
      print_newline () 
      
    let write buf t = 
      Printf.bprintf buf "$Get %s$%ld" t.name t.pos
    
  end
  
module FileLength = struct
    type t = int32
      
    let parse s = Int32.of_string s
      
    let print t = 
      Printf.printf "FileLength %ld" t;
      print_newline () 
      
    let write buf t = 
      Printf.bprintf buf "$FileLength %ld" t
    
  end


module Key = struct
    type t = {
        key : string;
      }
      
    let parse key = { key = key }
      
    let print t = 
      Printf.printf "KEY [%s]" (String.escaped t.key) ;
      print_newline () 
      
    let write buf t = 
      Printf.bprintf buf " %s" t.key
    
  end


module To = struct
    type t = {
        dest : string;
        orig : string;
        message : string;
      }
      
    let parse s = 
      match String2.splitn s ' ' 3 with
      | [dest; "From:"; orig; m] -> 
          let m = String.sub m 1 (String.length m - 1) in
          { dest = dest; orig = orig; message = m }
      | _ -> assert false
      
    let print t = 
      Printf.printf "To %s FROM %s: %s" t.dest t.orig t.message;
      print_newline () 
      
    let write buf t = 
      Printf.bprintf buf " %s From: %s $%s" t.dest t.orig t.message
    
  end

module Search = struct
    type t = {
        orig : string;
        sizelimit : sizelimit;
        filetype : int;
        words : string;
      }
      
    let parse s = 
      Printf.printf "SEARCH: [%s]" (String.escaped s); print_newline ();
      match String2.split_simplify s ' ' with
      | [orig; search] ->
          begin
            match String2.splitn search '?' 4 with
              [has_size; size_kind; size; filetype; words] ->
                String2.replace_char words '$' ' ';
                let size = 
                  match has_size, size_kind with
                     "T", "T" -> AtMost (Int32.of_string size)
                  |  "T", "F" -> AtLeast (Int32.of_string size)
                  | _ -> NoLimit
                in
                {
                  orig = orig;
                  sizelimit = size;
                  filetype = int_of_string filetype;
                  words = words;
                } 
            | _ -> assert false
          end
      | _ -> assert false
      
    let print t = begin
      match t.sizelimit with
      | AtLeast n ->
          Printf.printf "Search %s TYPE %d FOR %s of at least %ld" 
            t.orig t.filetype t.words n
      | AtMost n ->
          Printf.printf "Search %s TYPE %d FOR %s of at most %ld" 
            t.orig t.filetype t.words n
      | NoLimit ->
          Printf.printf "Search %s TYPE %d FOR %s" 
            t.orig t.filetype t.words
      end;          
      print_newline () 
      
    let write buf t = 
      Printf.bprintf buf " %s %c?%c?%s?%d?%s"
        t.orig 
        (if t.sizelimit = NoLimit then 'F' else 'T')
      (match t.sizelimit with
          AtMost _ -> 'T'        | _ -> 'F')
      (match t.sizelimit with
          AtMost n -> Int32.to_string n
        | AtLeast n -> Int32.to_string n
        | _  -> "0")
      t.filetype
        (let s = String.copy t.words in 
        String2.replace_char s ' ' '$'; s)
    
  end
    
module HubName = struct
    type t = {
        name : string;
      }
      
    let parse name = { name = name }
      
    let print t = 
      Printf.printf "HUB NAME [%s]" (String.escaped t.name) ;
      print_newline () 
      
    let write buf t = 
      Printf.bprintf buf " %s" t.name
    
  end
    
module NickList = struct
    type t = {
        users : string list;
      }
      
    let parse users = 
      { users = String2.split_simplify users '$'  }
          
    let print t = 
      Printf.printf "NICK LIST "; 
      List.iter (fun s -> Printf.printf "%s " s) t.users;
      print_newline () 
      
    let write buf t = 
      Buffer.add_char buf ' ';
      List.iter (fun s -> Printf.bprintf  buf "%s$$" s) t.users
    
  end
    
module OpList = struct
    type t = {
        users : string list;
      }
      
    let parse users = 
      { users = String2.split_simplify users '$'  }
          
    let print t = 
      Printf.printf "OP LIST "; 
      List.iter (fun s -> Printf.printf "%s " s) t.users;
      print_newline () 
      
    let write buf t = 
      Buffer.add_char buf ' ';
      List.iter (fun s -> Printf.bprintf  buf "%s$$" s) t.users
    
  end

let char5 = char_of_int 5
  
module SR = struct
    type t = {
        owner : string;
        filename : string;
        filesize : int32;
        used_slots : int;
        open_slots : int;
        server_name : string;
        server_ip : string option;
      }
      
    let parse s = 
      match String2.split s char5 with
        [owner_and_filename; size_and_slots; server_info] -> begin
            match String2.splitn owner_and_filename ' ' 1 with
              [owner; filename] -> begin
                  match String2.splitn size_and_slots ' ' 1 with
                    [size; slots] -> begin
                        match String2.splitn slots '/' 1 with
                          [used_slots; open_slots] -> begin
                              match String2.split server_info ' ' with
                                server_name :: server_tail ->
                                  {
                                    owner = owner;
                                    filename = filename;
                                    filesize = Int32.of_string size;
                                    used_slots = int_of_string used_slots;
                                    open_slots = int_of_string open_slots;
                                    server_name = server_name;
                                    server_ip = match server_tail with
                                      [] -> None
                                    | [server_ip] ->
                                        let len = String.length server_ip in
                                        if len > 2 then
                                          Some (String.sub server_ip 1 (len-2))
                                        else None
                                    | _ -> None
                                  }
                                  
                              | _ -> assert false
                            end
                        | _ -> assert false
                      end
                  | _ -> assert false
                end
            | _ -> assert false
          end
      | _ -> assert false
      
    let print t = 
      Printf.printf "SEARCH REPLY On %s (%d/%d): %s %ld" 
        t.owner t.used_slots t.open_slots t.filename 
        t.filesize;
      print_newline () 
      
    let write buf t = 
      Printf.bprintf buf " %s %s%c%s %d/%d%c%s%s" 
        t.owner t.filename char5 (Int32.to_string t.filesize)
      t.used_slots t.open_slots char5 t.server_name
        (match t.server_ip with
          None -> ""
        | Some server_ip -> Printf.sprintf " (%s)" server_ip)
    
  end
    
module Version = struct
    type t = {
        version : string;
      }
      
    let parse version = { version = version }
      
    let print t = 
      Printf.printf "VERSION [%s]" (String.escaped t.version) ;
      print_newline () 
      
    let write buf t = 
      Printf.bprintf buf " %s" t.version
    
  end
  
module MyINFO = struct
    type t = {
        dest : string; (* $ALL *)
        nick : string;
        description : string;
        speed : string;
        kind : int;
        email : string;
        size : float;
      }

      (*
    let rec get_ending_dollar list t =
      match list with
        [] -> assert false
      | s :: tail ->
          let len = String.length s in
          assert (len > 0);
          if t.description = "" then            
            if s.[len-1] = '$' then
              {t with 
                description = String.sub s 0 (len-1) }, tail
            else
              get_ending_dollar tail { t with description = s }
          
          else
          if s.[len-1] = '$' then
            {t with 
              description = Printf.sprintf "%s %s" t.description 
                (String.sub s 0 (len-1))
            
            }, tail
          else
            get_ending_dollar tail { t with 
              description = Printf.sprintf "%s %s" t.description s }
            
    let dummy = {
        dest = "$ALL";
        nick = "";
        description = "";
        speed = "";
        kind = Normal;
        email = "";
        size = Int64.zero;
      }
*)
      
    let parse s = 
      match String2.split s '$' with
      | _ :: part1 :: _ :: part2 :: email :: part3 :: _ ->
          begin
            match String2.splitn part1 ' ' 2 with
              dest :: nick :: desc :: [] ->
                let len2 = String.length part2 in
                let speed = String.sub part2 0 (len2-1) in
                let kind = int_of_char part2.[len2-1] in
                let size = float_of_string part3 in
                { 
                  dest = dest;
                  nick = nick;
                  description = desc;
                  speed = speed;
                  kind = kind;
                  size = size;
                  email = email;
                }
            | _ -> assert false
          end
          
      | list -> List.iter (fun s -> Printf.printf "{%s}" 
              (String.escaped s)) list;
          print_newline ();
          raise Not_found

          
        (*

        {}{ALL mldonkey_jetti_0 mldonkey client}{ }{DSL\006}{}{20000000000}{}
        [] | [_] -> assert false
      | dest :: nick :: tail -> 
          let t, tail = get_ending_dollar tail { dummy with
              dest = dest; nick = nick } in
          match tail with
            [tail] ->
              begin
                match String2.split tail '$' with
                  [""; speed; email; size; ""] ->
                    let len = String.length speed in
                    {
                      t with
                      speed = String.sub speed 0 (len-1);
                      kind = kind_of_char speed.[len-1];
                      size = Int64.of_string size;
                    }
                | _ -> assert false
              end
          | _ -> assert false
*)
        
    let print t = 
      Printf.printf "MyINFO %s %s %s %s %f" 
        t.dest t.nick t.description t.speed t.size;
      print_newline () 
    
    let write buf t = 
      Printf.bprintf buf " %s %s %s$ $%s%c$%s$%10.0f$" 
        t.dest t.nick t.description t.speed
        (char_of_int t.kind) t.email t.size
      
  end

    
module NickAndAddr(M: sig val msg : string end) = struct
      
    type t = {
        nick : string;
        ip : Ip.t;
        port : int;
      }
      
    let parse s = 
      let (nick, rem) = String2.cut_at s ' ' in
      let (ip, port) = String2.cut_at rem ':' in
      {
        nick = nick;
        ip = Ip.of_string ip;
        port = int_of_string port;
      }
      
    let print t = 
      Printf.printf "%s %s %s:%d" M.msg t.nick (Ip.to_string t.ip) t.port;
      print_newline () 
      
    let write buf t = 
      Printf.bprintf  buf "$%s %s %s:%d" M.msg t.nick (Ip.to_string t.ip) t.port;
    
  end
    
module RevConnectToMe = struct
      
    type t = {
        dest : string;
        orig : string;
      }
      
    let parse s = 
      let (dest, orig) = String2.cut_at s ' ' in
      {
        dest = dest;
        orig = orig;
      }
      
    let print t = 
      Printf.printf "RevConnectToMe %s %s" t.dest t.orig;
      print_newline () 
      
    let write buf t = 
      Printf.bprintf  buf "$RevConnectToMe %s %s"  t.dest t.orig;
    
  end
    
module ConnectToMe = NickAndAddr(struct let msg = "ConnectToMe" end)
module MultiConnectToMe = NickAndAddr(struct let msg = "MultiConnectToMe" end)
  
module Msg = struct
    type t = ()
      
    let parse s = ()
      
    let print t = ()
      
    let write buf t = ()
    
  end

module MyNick = SimpleNick2(struct let msg = "MyNick" end)
module ValidateNick = SimpleNick(struct let msg = "ValidateNick" end)
module ForceMove = SimpleNick(struct let msg = "ForceMove" end)
module Hello = SimpleNick(struct let msg = "Hello" end)
module Quit = SimpleNick(struct let msg = "Quit" end)
module GetNickList = Empty(struct let msg = "GetNickList" end)
  
module GetListLen = Empty2(struct let msg = "GetListLen" end)
module MaxedOut = Empty2(struct let msg = "MaxedOut" end)
module Send = Empty2(struct let msg = "Send" end)
module Canceled = Empty2(struct let msg = "Canceled" end)
  
type t =
| LockReq of Lock.t
| KeyReq of Key.t
| MyNickReq of MyNick.t
| ValidateNickReq of ValidateNick.t
| ForceMoveReq of ForceMove.t
| HelloReq of Hello.t
| QuitReq of Quit.t
| ToReq of To.t

| GetNickListReq
| NickListReq of NickList.t
| OpListReq of OpList.t
| VersionReq of Version.t
| SRReq of SR.t

| SearchReq of Search.t
| MultiSearchReq of Search.t
| HubNameReq of HubName.t
| MessageReq of string
| MyINFOReq of MyINFO.t
| UnknownReq of string

| RevConnectToMeReq of RevConnectToMe.t
| ConnectToMeReq of ConnectToMe.t
| MultiConnectToMeReq of MultiConnectToMe.t

| GetReq of Get.t
| FileLengthReq of FileLength.t
| DirectionReq of Direction.t
| GetListLenReq
| MaxedOutReq
| SendReq
| CanceledReq
  
let parse s = 
  try
(*
  Printf.printf "PARSE:"; print_newline ();
AgProtocol.dump s;
  *)
    let ws = String2.splitn s ' ' 1 in
    match ws with
    | [] -> UnknownReq s
    | [cmd ; args] ->
        if String.length cmd > 0 then
          if cmd.[0] = '$' then
            match cmd with
            | "$Lock" -> LockReq (Lock.parse args)
            | "$Key" -> KeyReq (Key.parse args)
            | "$MyNick" -> MyNickReq (MyNick.parse args)

            | "$GetNickList" -> GetNickListReq
            | "$NickList" -> NickListReq (NickList.parse args)
            | "$OpList" -> OpListReq (OpList.parse args)
            | "$Version" -> VersionReq (Version.parse args)
            | "$SR" -> SRReq (SR.parse args)

            | "$ValidateNick" -> ValidateNickReq (ValidateNick.parse args)
            | "$ForceMove" -> ForceMoveReq (ForceMove.parse args)
            | "$Hello" -> HelloReq (Hello.parse args)
            | "$Quit" -> QuitReq (Quit.parse args)
            | "$HubName" -> HubNameReq (HubName.parse args)
            | "$MyINFO" -> MyINFOReq (MyINFO.parse args)
            | "$To:" -> ToReq (To.parse args)
            | "$Search" -> SearchReq (Search.parse args)
            | "$MultiSearch" -> MultiSearchReq (Search.parse args)

                
            | "$Get" -> GetReq (Get.parse args)
            | "$FileLength" -> FileLengthReq (FileLength.parse args)
            | "$Direction" -> DirectionReq (Direction.parse args)
            | "$GetListLen" -> GetListLenReq
            | "$MaxedOut" -> MaxedOutReq
            | "$Send" -> SendReq
            | "$Canceled" -> CanceledReq

                
            | "$RevConnectToMe" -> RevConnectToMeReq (RevConnectToMe.parse args)
            | "$ConnectToMe" -> ConnectToMeReq (ConnectToMe.parse args)
            | "$MultiConnectToMe" -> MultiConnectToMeReq 
                (MultiConnectToMe.parse args)
            | _ -> UnknownReq s
          else
            MessageReq s
        else UnknownReq s
    | _ -> UnknownReq s
  with e ->
      Printf.printf "Exception %s in parse" (Printexc.to_string e);
      print_newline ();
      UnknownReq s
      
let write buf m =
  match m with
    LockReq t -> Buffer.add_string buf "$Lock"; Lock.write buf t
  | KeyReq t -> Buffer.add_string buf "$Key"; Key.write buf t
  | MyNickReq t -> MyNick.write buf t
  | HelloReq t -> Buffer.add_string buf "$Hello"; Hello.write buf t
  | QuitReq t -> Buffer.add_string buf "$Quit"; Quit.write buf t
  | SearchReq t -> Buffer.add_string buf "$Search"; Search.write buf t
  | MultiSearchReq t -> Buffer.add_string buf "$MultiSearch"; Search.write buf t
  | MyINFOReq t -> Buffer.add_string buf "$MyINFO"; MyINFO.write buf t
  | ForceMoveReq t -> Buffer.add_string buf "$ForceMove"; ForceMove.write buf t
  
  | RevConnectToMeReq t -> RevConnectToMe.write buf t
  | ConnectToMeReq t -> ConnectToMe.write buf t
  | MultiConnectToMeReq t -> MultiConnectToMe.write buf t
  
  
  | GetReq t -> Get.write buf t
  | FileLengthReq t -> FileLength.write buf t
  | DirectionReq t -> Direction.write buf t
  | GetListLenReq -> GetListLen.write buf ()
  | MaxedOutReq -> MaxedOut.write buf ()
  | SendReq -> Send.write buf ()
  | CanceledReq -> Canceled.write buf ()
    
      
  | GetNickListReq -> Buffer.add_string buf "$GetNickList"
  | NickListReq t -> 
      Buffer.add_string buf "$NickList"; 
      NickList.write buf t
  | OpListReq t -> Buffer.add_string buf "$OpList"; OpList.write buf t
  | VersionReq t -> Buffer.add_string buf "$Version"; Version.write buf t
  | SRReq t -> Buffer.add_string buf "$SR"; SR.write buf t
      
    
      | ToReq t -> Buffer.add_string buf "$To:"; To.write buf t
  | ValidateNickReq t -> 
      Buffer.add_string buf "$ValidateNick"; ValidateNick.write buf t
  | HubNameReq t -> 
      Buffer.add_string buf "$HubName"; HubName.write buf t
  | MessageReq t -> Buffer.add_string buf t
  | UnknownReq t -> Buffer.add_string buf t

let print m =
  begin
    match m with
      LockReq t -> Lock.print t
    | KeyReq t -> Key.print t
    | HelloReq t -> Hello.print t
    | QuitReq t -> Quit.print t
    | MyNickReq t -> MyNick.print t
                
    | GetNickListReq -> GetNickList.print ()
    | NickListReq t -> NickList.print t
    | OpListReq t -> OpList.print t
    | VersionReq t -> Version.print t
    | SRReq t -> SR.print t
    | ForceMoveReq t -> ForceMove.print t

          
  | GetReq t -> Get.print t
  | FileLengthReq t -> FileLength.print t
  | DirectionReq t -> Direction.print t
  | GetListLenReq -> GetListLen.print ()
  | MaxedOutReq -> MaxedOut.print ()
  | SendReq -> Send.print ()
  | CanceledReq -> Canceled.print ()

        
    | RevConnectToMeReq t -> RevConnectToMe.print t
    | ConnectToMeReq t -> ConnectToMe.print t
    | MultiConnectToMeReq t -> MultiConnectToMe.print t
        
        
    | SearchReq t -> Search.print t
    | MultiSearchReq t -> Printf.printf "MULTI "; Search.print t
    | MyINFOReq t -> MyINFO.print t
    | ValidateNickReq t -> ValidateNick.print t
    | HubNameReq t -> HubName.print t
    | ToReq t -> To.print t
    | MessageReq t -> Printf.printf "MESSAGE: %s" t
    | UnknownReq t -> Printf.printf "UNKNOWN:"; 
        BigEndian.dump t
  end;
  print_newline () 
  
let dc_handler f sock nread =
  let b = TcpBufferedSocket.buf sock in
  try
    let rec iter nread =
      if nread > 0 then begin
          let pos = String.index_from b.buf (b.pos + b.len - nread) '|' in
          if pos < b.pos + b.len then
            let s = String.sub b.buf b.pos (pos - b.pos) in
            buf_used sock (pos - b.pos + 1);
            f (parse s) sock;
            iter b.len
        end
    in
    iter nread
  with Not_found -> ()

let dc_handler3 c ff f r sock nread =
  let b = TcpBufferedSocket.buf sock in
  try
    let rec iter nread =
      if nread > 0 then 
        match !c with 
          Some c when c.client_receiving <> Int32.zero ->
            r c sock nread
        | _ ->
            let pos = String.index_from b.buf (b.pos + b.len - nread) '|' in
            if pos < b.pos + b.len then
              let s = String.sub b.buf b.pos (pos - b.pos) in
              buf_used sock (pos - b.pos + 1);
              let m = parse s in
              match !c with
                None -> 
                  c := ff m sock;
                  iter b.len
              | Some c ->
                  f c m sock;
                  iter b.len
    
    in
    iter nread
  with Not_found -> ()
      
let buf = Buffer.create 100
      
let server_send sock m =
  Printf.printf "SENDING"; print_newline ();
  print m;
  Buffer.clear buf;
  write buf m;
  Buffer.add_char buf '|';
  let s = Buffer.contents buf in
  Printf.printf "BUFFER SENT[%s]" (String.escaped s); print_newline ();
  write_string sock s

(*


[$Hello mldonkey_lwwms_2]
  
[$Hello mldonkey_lwwms_2]
  
[$To: mldonkey_lwwms_2 From: Hub $Welcome to The Scorpion's Den           ----         http://ScorpionsDen.d2g.com]
  
[$To: mldonkey_lwwms_2 From: Hub $Welcome to The Scorpion's Den           ----         http://ScorpionsDen.d2g.com]
  
[$Hello mldonkey_lwwms_4]
  
[$Hello mldonkey_lwwms_4]
  
[$To: mldonkey_lwwms_4 
From: Hub 
$ Witaj na PoLiSh SeXy WaReZ CLUB 2(13)(10)
(13)(10)
zapraszamy na stronke(13)(10)
http://www.polish-warez-club.prv.pl(13)(10)
POLECAM KSIEGE GOSCI !!!(13)(10)
(13)(10)
===============================(13)(10)
Admin Kojot(13)(10)
  GG:11750(13)(10)===============================(13)(10) Minimalna ilosc plikow/slotow (13)(10) dla wszystkich rodzajow laczy:(13)(10)    min. 8GB, 4 sloty(13)(10)===============================(13)(10)Wszyscy uzytkownicy poslugujacy sie (13)(10)DC++ Limit wynosi 2 Huby w jednej sesji(13)(10)===============================(13)(10)(13)(10) Podawanie falszywego opisu(13)(10) lacza, rozlaczanie transferow,(13)(10) blokady portow DC na firewallu,(13)(10) udostepnianie smieci, katalogu(13)(10) Windowsa czy Program Files -  (13)(10) zakonczy BAN bez dyskusji.(13)(10)(13)(10) Uzytkownicy laczacy sie w trybie(13)(10) Passive powinni miec w nicku(13)(10) dolaczone: pas, psv lub passive(13)(10)(13)(10) W description - nazwa operatora(13)(10) internetu (opcjonalnie: miasto)(13)(10)(13)(10) Jesli nie lamiesz w/w zasad, jestes(13)(10) tu mile widziany, zapraszamy :)(13)(10)(13)(10)]
  
[$To: mldonkey_lwwms_4 From: Hub $ Witaj na PoLiSh SeXy WaReZ CLUB 2(13)(10)                       (13)(10)zapraszamy na stronke(13)(10)http://www.polish-warez-club.prv.pl(13)(10)POLECAM KSIEGE GOSCI !!!(13)(10)(13)(10)===============================(13)(10)Admin Kojot(13)(10)GG:11750(13)(10)===============================(13)(10) Minimalna ilosc plikow/slotow (13)(10) dla wszystkich rodzajow laczy:(13)(10)    min. 8GB, 4 sloty(13)(10)===============================(13)(10)Wszyscy uzytkownicy poslugujacy sie (13)(10)DC++ Limit wynosi 2 Huby w jednej sesji(13)(10)===============================(13)(10)(13)(10) Podawanie falszywego opisu(13)(10) lacza, rozlaczanie transferow,(13)(10) blokady portow DC na firewallu,(13)(10) udostepnianie smieci, katalogu(13)(10) Windowsa czy Program Files -  (13)(10) zakonczy BAN bez dyskusji.(13)(10)(13)(10) Uzytkownicy laczacy sie w trybie(13)(10) Passive powinni miec w nicku(13)(10) dolaczone: pas, psv lub passive(13)(10)(13)(10) W description - nazwa operatora(13)(10) internetu (opcjonalnie: miasto)(13)(10)(13)(10) Jesli nie lamiesz w/w zasad, jestes(13)(10) tu mile widziany, zapraszamy :)(13)(10)(13)(10)]
  
[$Search Hub:Livek-slot F?F?0?0?.]
  
[$Search Hub:Livek-slot F?F?0?0?.]
  
[$Search Hub:Livek-slot F?F?0?0?mp3]
  
[$Search Hub:Livek-slot F?F?0?0?mp3]
  
[$Search Hub:Livek F?F?0?0?config.cfg]
  
[$Search Hub:Livek F?F?0?0?config.cfg]
  
[]
  
[]
[$Search Hub:Livek F?F?0?0?pak1.pk3]
  
[$Search Hub:Livek F?F?0?0?pak1.pk3]
[]
[]
[$Search Hub:Livek F?F?0?0?Opengl32.dll]
  
[$Search Hub:Livek F?F?0?0?Opengl32.dll]
[]
[]
[$Search Hub:Livek F?F?0?0?unrealtournament.ini]
  
[$Search Hub:Livek F?F?0?0?unrealtournament.ini]
[]
[]
[$Search Hub:Livek Guardian F?F?0?0?iexplore.exe]
  
[$Search Hub:Livek Guardian F?F?0?0?iexplore.exe]
[]
[]
[$Search Hub:Livek Guardian F?F?0?0?explorer.exe]
  
[$Search Hub:Livek Guardian F?F?0?0?explorer.exe]
[]
[]
[$Hello mldonkey_lwwms_9]
[$Hello mldonkey_lwwms_9]
  
[$To: mldonkey_lwwms_9 From: Hub $welcome to uk unoffical fg4a pub(13)(10)(13)(10) server addy    UKUnofficialFG4aHub.no-ip.com(13)(10)(13)(10)4gb shard   2 slots   members only(13)(10)no porn  & no installed files(13)(10)(13)(10)(13)(10)(13)(10)i will try to keep  up as long as i can  guys ...(13)(10)(13)(10)        (13)(10)(13)(10)  run by snake(13)(10)]
  
[$To: mldonkey_lwwms_9 From: Hub $welcome to uk unoffical fg4a pub(13)(10)(13)(10) server addy    UKUnofficialFG4aHub.no-ip.com(13)(10)(13)(10)4gb shard   2 slots   members only(13)(10)no porn  & no installed files(13)(10)(13)(10)(13)(10)(13)(10)i will try to keep  up as long as i can  guys ...(13)(10)(13)(10)        (13)(10)(13)(10)  run by snake(13)(10)]
  
[$Hello mldonkey_lwwms_13]
  
[$Hello mldonkey_lwwms_13]
  
[$To: mldonkey_lwwms_13 From: Hub $Disclaimer>(13)(10)You may not enter this server if you are affiliated with, represent, or are visiting on behalf of;(13)(10)(1) Any form of law enforcement agency. (13)(10)(2) Any software corporation. (13)(10)(3) Any type of Internet Security Expert or hacker.(13)(10)This server, and the activities that it is intended for, is in all ways legal.(13)(10)We do not condone nor encourage the distribution of "warez" or copyright works.(13)(10)If any user participates in the illegal sharing of data, they assume any and all responsiblity for their actions.(13)(10)If you enter this private server and you are not agreeing to these terms, you are violating code 431.322.12 of the Internet Privacy Act signed by Bill Clinton in 1995 which stipulates that you can NOT threaten anyone storing these files, and cannot prosecute any person(s) affiliated or connected to this server.(13)(10)By Entering you are agreeing to the above; If not, you must exit immediately!(13)(10)(13)(10)(13)(10)Welcome to -=PS2/FTP Trade & Share=- Hub(13)(10)(13)(10)                   -= General Rules =-(13)(10)(13)(10)     (149) Don(180)t Share Child Or Preteen Pornography. (less then 18 Years of age)(13)(10)     (149) Don(180)t Share Installed Or Incomplete Files.(13)(10)     (149) Don(180)t Share Snuff, Rape, Animal, Or Other Sick Porn.(13)(10)     (149) Do NOT Fake Your Share Limit Or Share VOB Files.(13)(10)     (149) Don(180)t Flooding Or Use Bad Language In The Main-Chat Window.(13)(10)     (149) Make Certain That It(180)s Possible For Other To Download Your DC List When There Is A Free Slot.(13)(10)     (149) Use search. Don(180)t Ask In Chat... Unless You Can(180)t Find It.(13)(10)     (149) Stay In The Hub While You Are Downloading.(13)(10)     (149) Report to Ops if someone is advertising or just fucks with U.(13)(10)     (149) Don't Bother An OP Unless It's Important.(13)(10)     (149) Run Neo-Modus Client Not DC++ Or Open DC(13)(10)(13)(10)HUB NEWS:(13)(10)(13)(10)New Look Better Scripts!! :-)(13)(10)Thanks Go Out To Erario For The No!! Dc++ Script..:-)  ..Thanks Mate Dont No What We Do Without Ya!!]

[$To: mldonkey_lwwms_13 From: Hub $Disclaimer>(13)(10)You may not enter this server if you are affiliated with, represent, or are visiting on behalf of;(13)(10)(1) Any form of law enforcement agency. (13)(10)(2) Any software corporation. (13)(10)(3) Any type of Internet Security Expert or hacker.(13)(10)This server, and the activities that it is intended for, is in all ways legal.(13)(10)We do not condone nor encourage the distribution of "warez" or copyright works.(13)(10)If any user participates in the illegal sharing of data, they assume any and all responsiblity for their actions.(13)(10)If you enter this private server and you are not agreeing to these terms, you are violating code 431.322.12 of the Internet Privacy Act signed by Bill Clinton in 1995 which stipulates that you can NOT threaten anyone storing these files, and cannot prosecute any person(s) affiliated or connected to this server
  .(13)(10)By Entering you are agreeing to the above; If not, you must exit immediately!(13)(10)(13)(10)(13)(10)Welcome to -=PS2/FTP Trade & Share=- Hub(13)(10)(13)(10)                   -= General Rules =-(13)(10)(13)(10)     (149) Don(180)t Share Child Or Preteen Pornography. (less then 18 Years of age)(13)(10)     (149) Don(180)t Share Installed Or Incomplete Files.(13)(10)     (149) Don(180)t Share Snuff, Rape, Animal, Or Other Sick Porn.(13)(10)     (149) Do NOT Fake Your Share Limit Or Share VOB Files.(13)(10)     (149) Don(180)t Flooding Or Use Bad Language In The Main-Chat Window.(13)(10)     (149) Make Certain That It(180)s Possible For Other To Download Your DC List When There Is A Free Slot.(13)(10)     (149) Use search. Don(180)t Ask In Chat... Unless You Can(180)t Find It.(13)(10)     (149) Stay In The Hub While You Are Downloading.(13)(10)     (149) Report to Ops if someone is advertising or just fucks with U.(13)(10)     (149) Don't Bother An OP Unless It's Important.(13)(10)     (149) Run Neo-Modus Client Not DC++ Or Open DC(13)(10)(13)(10)HUB NEWS:(13)(10)(13)(10)New Look Better Scripts!! :-)(13)(10)Thanks Go Out To Erario For The No!! Dc++ Script..:-)  ..Thanks Mate Dont No What We Do Without Ya!!]

[$To: mldonkey_lwwms_13 From: -=Hub-Guard=- $<-=Hub-Guard=-> Welcome to -=PS2/FTP Trade & Share=-(13)(10)(13)(10)This Hub is dedicated to all PS2 Gamers. Follow the rules and you will not get banned. Have fun!(13)(10)(13)(10)(13)(10)(13)(10)Rule #1:   Minimum 5 Gb of PS2 Games (10 complete games, image or rar files)   ** SCRIPTED **(13)(10)Rule #2:   Keep at least 3 or more slots open   ** SCRIPTED **(13)(10)Rule #3:   Always open a slot for the OP for download or checking your files(13)(10)Rule #4:   Stay in the Hub during download(13)(10)Rule #5:   No DialUp connection, sorry :-(   ** SCRIPTED **(13)(10)Rule #6:   Don't share your Windows folder and installed Appz!   ** SCRIPTED **(13)(10)Rule #7:   If you get KICKED, wait until the 15 min Temp Ban!!(13)(10)Rule #8:   Don't Advertise For Other Channels Or You Will Be Banned(13)(10)Rule #9:   No Flooding Or Bad Language In The Main-Chat Window you 3 Warnings Then Kick!!(13)(10)Rule #10:  Don(180)t ask to be an OP! If you seem to be a good candidate for an OP, we will come to you.(13)(10)(13)(10)Type +help in main chat window to see commands]
  
[$To: mldonkey_lwwms_13 From: -=Hub-Guard=- $<-=Hub-Guard=-> Welcome to -=PS2/FTP Trade & Share=-(13)(10)(13)(10)This Hub is dedicated to all PS2 Gamers. Follow the rules and you will not get banned. Have fun!(13)(10)(13)(10)(13)(10)(13)(10)Rule #1:   Minimum 5 Gb of PS2 Games (10 complete games, image or rar files)   ** SCRIPTED **(13)(10)Rule #2:   Keep at least 3 or more slots open   ** SCRIPTED **(13)(10)Rule #3:   Always open a slot for the OP for download or checking your files(13)(10)Rule #4:   Stay in the Hub during download(13)(10)Rule #5:   No DialUp connection, sorry :-(   ** SCRIPTED **(13)(10)Rule #6:   Don't share your Windows folder and installed Appz!   ** SCRIPTED **(13)(10)Rule #7:   If you get KICKED, wait until the 15 min Temp Ban!!(13)(10)Rule #8:   Don't Advertise For Other Channels Or You Will Be Banned(13)(10)Rule #9:   No Flooding Or Bad Language In The Main-Chat Window you 3 Warnings Then Kick!!(13)(10)Rule #10:  Don(180)t ask to be an OP! If you seem to be a good candidate for an OP, we will come to you.(13)(10)(13)(10)Type +help in main chat window to see commands]  
[$Search Hub:SickoBot F?F?0?0?preteen]  
[$Search Hub:SickoBot F?F?0?0?preteen]  
[$Search Hub:SickoBot F?F?0?0?incest ]  
[$Search Hub:SickoBot F?F?0?0?incest ]  
[$Search Hub:SlotBot F?F?0?0?avi]
[$Search Hub:SlotBot F?F?0?0?avi]
[$Search Hub:SlotBot F?F?0?0?mp3]
[$Search Hub:SlotBot F?F?0?0?mp3]
[$To: mldonkey_lwwms_13 From: WatchBot $<WatchBot> Hi there!  I will watch for users or files which are not here, and then tell you when they come online.  Here are the commands:(13)(10)  watchuser <user_name>(9)- adds a user to my list(13)(10)  watchfile <file_name>(9)- adds a file to my list(13)(10)  watchreset(9)(9)- clears the list(13)(10)]
[$To: mldonkey_lwwms_13 From: WatchBot $<WatchBot> Hi there!  I will watch for users or files which are not here, and then tell you when they come online.  Here are the commands:(13)(10)  watchuser <user_name>(9)- adds a user to my list(13)(10)  watchfile <file_name>(9)- adds a file to my list(13)(10)  watchreset(9)(9)- clears the list(13)(10)]

[$MyINFO $ALL ___Hub_Info___ Hub Information System$ $Hub Info Sys(9)$$0$]
[$MyINFO $ALL ___Hub_Info___ Hub Information System$ $Hub Info Sys(9)$$0$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL ___Hub_Info___ Hub Information System$ $Hub Info Sys(9)$$0$]
[$MyINFO $ALL ___Hub_Info___ Hub Information System$ $Hub Info Sys(9)$$0$]
[$ForceMove get-it-here.no-ip.com]
[$ForceMove get-it-here.no-ip.com]
[$MyINFO $ALL [SDSL]hubby  $  DSL(1)$$174688203491$]
[$MyINFO $ALL [SDSL]hubby  $  DSL(1)$$174688203491$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL KickBot Der B(246)se Bot$$Bot(1)$deutschland-cafe@web.de$1,04$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]
[$MyINFO $ALL tantchen Der nette Bot$ $Bot(1)$deutschland-cafe@web.de$1,10$]

*)