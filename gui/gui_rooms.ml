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

(** GUI for the lists of files. *)

open Gettext
open CommonTypes
open GuiTypes
open Gui_columns

module M = Gui_messages
module P = Gpattern
module O = Gui_options
module Mi = Gui_misc
module G = Gui_global

let (!!) = Options.(!!)

class box tb_style () =
  object(self)
    inherit Gui_rooms_base.box tb_style () 
    
    method set_tb_style (tb_style : Gtk.Tags.toolbar_style) = ()
end
  
  (*

class paned () =
  let vbox = GPack.vbox ~homogeneous:false () in
  let wpane =
    GPack.paned `HORIZONTAL ~packing:(vbox#pack ~expand:true ~fill:true) ()
  in
  object
    val vbox = vbox
    val wpane = wpane
    method vbox = vbox
    method wpane = wpane
    method coerce = vbox#coerce
end;;


let rooms_by_num = Hashtbl.create 113

class pane_room (room : room_info) =
  let close = ref (fun _ -> ()) in
  let users = new box_users close in
  let messages = new box () () in
  object (self)
    inherit paned  ()
    
    method box_messages = messages
    method box_users = users
    method hpaned = wpane
    
    val mutable position = 0
    
    method insert_text ?user ?(priv=false) s =
      let user_info = 
	match user with
	  None -> None
	| Some u ->
	    let col = Gui_misc.color_of_name u in
	    Some (col,
		  Printf.sprintf "%s%s :" u
		    (if priv then " (private)" else ""))
      in
      (
       match user_info with
	 None -> ()
       | Some (c,s) ->
	   messages#wt_10#insert ~foreground: c s
      );
      messages#wt_10#insert s
    
    
    method on_entry_return () =
      match messages#we_11#text with
        "" -> ()
      |	s ->
          Gui_com.send
	    (GuiProto.SendMessage (room.room_num, 
				    PublicMessage (0,s)));
          messages#we_11#set_text "";
          (*self#insert_text (Printf.sprintf "> %s\n" s) *)
          
    initializer
      Okey.add messages#we_11
        ~mods: []
        GdkKeysyms._Return
        self#on_entry_return      
    
    
    method set_tb_style st = 
      users#set_tb_style st ;
      messages#set_tb_style st

(** {2 Handling core messages} *)

(*
    method h_user_info = servers#h_server_info
    method h_server_state = servers#h_server_state
    method h_server_busy = servers#h_server_busy
    method h_server_user = servers#h_server_user
*)
        
    method update_users =
      let list = ref [] in
      List.iter (fun u ->
          try
            let user_info = Hashtbl.find G.users u in
            list := user_info :: !list
          with _ ->
              Gui_com.send (GuiProto.GetUser_info u);
      ) room.room_users;
      users#update_data !list

    method remove_user num =
      if List.memq num room.room_users then begin
          room.room_users <- List2.removeq num room.room_users;
          self#update_users              
        end
    
    method coerce = self#vbox#coerce
    
    initializer
      wpane#add1 users#coerce;
      wpane#add2 messages#coerce;
      close := (fun _ -> 
          let vbox = Hashtbl.find rooms_by_num room.room_num in
          vbox#coerce#destroy ();
	  Hashtbl.remove rooms_by_num room.room_num
      )
end
      
  
let add_room_user num user_num =
  try
    let vbox = Hashtbl.find rooms_by_num num in
    try
      vbox#add_user user_num
    with _ -> 
        Printf.printf "No such user %d" user_num;
        print_newline ();
  with _ -> 
      Printf.printf "No such room %d" num;
      print_newline ()
      
let user_info user = 
  ()  
(*
  match user.user_state with
    RemovedHost -> 
      Hashtbl.iter (fun num vbox ->
          vbox#remove_user user.user_num
          
      ) rooms_by_num
  | _ -> ()
*)      
  *)


(*********************************************************************)
(*********************************************************************)
(*********************************************************************)
(*********************************************************************)
(*********************************************************************)
(*********************************************************************)
(*********************************************************************)      

class rooms_box columns () =
  
  let titles = List.map Gui_columns.Room.string_of_column columns in 
  object (self)
    inherit [GuiTypes.room_info] Gpattern.plist `SINGLE titles true as pl
      inherit Gui_users_base.box () as box
    
    val mutable columns = columns
    method set_columns l =
      columns <- l;
      self#set_titles (List.map Gui_columns.Room.string_of_column columns);
      self#update
    
    method compare_by_col col f1 f2 =
      match col with
        Col_room_name -> compare f1.room_name f2.room_name
      | Col_room_network -> compare f1.room_network f2.room_network
      | Col_room_nusers -> compare f1.room_nusers f2.room_nusers
    
    
    method compare f1 f2 =
      let abs = if current_sort >= 0 then current_sort else - current_sort in
      let col = 
        try List.nth columns (abs - 1) 
        with _ -> Col_room_name
      in
      let res = self#compare_by_col col f1 f2 in
      res * current_sort
    
    method content_by_col f col =
      match col with
        Col_room_name -> f.room_name
      | Col_room_network -> G.network_name f.room_network
      | Col_room_nusers -> string_of_int f.room_nusers    
          
    method content f =
      let strings = List.map 
          (fun col -> P.String (self#content_by_col f col))
        columns 
      in
      let col_opt = Some `BLACK      in
      (strings, col_opt)

(*
    method compare u1 u2 =
      let res = match current_sort with
      |	1 | -1 -> compare (Ip.valid u1.user_ip) (Ip.valid u2.user_ip)
      |	2 | -2 -> compare u1.user_name u2.user_name
      |	_ -> 0
      in
      res * current_sort

    method content u =
      let s_kind = 
	if Ip.valid u.user_ip then 
          M.direct
	else ""
      in
      let s_name = u.user_name in
      [ P.String s_kind ; P.String s_name ; ], None
    
    method add_to_friends () =
      List.iter 
	(fun u -> Gui_com.send (GuiProto.AddUserFriend u.user_num))
	self#selection
    
    method browse_files () =
      List.iter 
        (fun u -> Gui_com.send (GuiProto.BrowseUser u.user_num))
      self#selection
      
    method menu =
      match self#selection with
	[] -> []
      |	_ -> [ 
            `I (M.add_to_friends, self#add_to_friends);
            `I (M.browse_files, self#browse_files)
          ]

    initializer
      box#vbox#pack ~expand: true pl#box ;
      ignore
	(wtool#insert_button 
	   ~text: M.add_to_friends
	   ~tooltip: M.add_to_friends
	   ~icon: (Gui_icons.pixmap M.o_xpm_add_to_friends)#coerce
	   ~callback: self#add_to_friends
	   ()
	);
*)
    
    val mutable filtered_data = []
    
    method find_room num =
      let rec iter n l =
        match l with
          [] -> 
            if n >= 0 then
              iter min_int filtered_data
            else raise Not_found
        | s :: q ->
            if s.room_num = num then
              (n, s)
            else
              iter (n+1) q
      in
      iter 0 data
    
    method add_room room =
      data <- data @ [room];
      self#insert ~row: self#wlist#rows room
    
    method remove_room row room =
      data <- List2.removeq room data;
      self#wlist#remove row
    
    method set_tb_style = wtool#set_style
    
    method clear = self#update_data []
    
    initializer
      box#vbox#pack ~expand: true pl#box ;

end

class box_rooms () =
  object (self)
    inherit rooms_box !!O.rooms_columns  ()
    
    initializer
      ()
end

class box_users selected_room =
  
  object (self)
    
    inherit Gui_users.box_users ()
    
    initializer
      
      ignore
        (wtool#insert_button 
          ~text: (gettext M.close_room)
          ~tooltip: (gettext M.close_room)
          ~icon: (Gui_icons.pixmap M.o_xpm_close_room)#coerce
          ~callback: (fun _ ->  
            match !selected_room with
              None -> ()
            | Some room ->
                Gui_com.send (GuiProto.SetRoomState (
                    room.room_num, RoomClosed)))
        ()
      );

end

class opened_rooms_box on_select =
  object (self)
    
    inherit box_rooms () as box_rooms
    
    method add_room room =
      box_rooms#add_room room;
      let w = box_rooms#wlist in
      w#select (w#rows - 1) 0

    method rooms = data
    method on_select room = on_select room
end

class paused_rooms_box () =
  object (self)
    
    inherit box_rooms ()
    
    method on_double_click room = 
      Gui_com.send (GuiProto.SetRoomState (room.room_num, RoomOpened))      

end

let add_room_user room user_num =
  if not (List.memq user_num room.room_users) then 
    room.room_users <- user_num :: room.room_users

class pane_room () =
  let selected_room = ref None in
  let box_room_users = new box_users selected_room in
  let messages = new box () () in
  
  object (self)
    inherit Gui_rooms_base.box2 ()

    method hpaned = hpaned
    
    method clear = 
      box_room_users#clear;
      try
        messages#wt_10#delete_text 0  messages#wt_10#length
      with e -> 
          Printf.printf "Exceptio %s in clear" (Printexc.to_string e);
          print_newline () 
    
    method insert_text ?user ?(priv=false) s =
      let user_info = 
        match user with
          None -> None
        | Some u ->
            let col = Gui_misc.color_of_name u in
            Some (col,
              Printf.sprintf "%s%s :" u
                (if priv then " (private)" else ""))
      in
      (
        match user_info with
          None -> ()
        | Some (c,s) ->
            messages#wt_10#insert ~foreground: c s
      );
      messages#wt_10#insert s
    
    
    method on_entry_return () =
      match !selected_room with
        None -> ()
      | Some room ->
          match messages#we_11#text with
            "" -> ()
          |	s ->
              Gui_com.send
                (GuiProto.SendMessage (room.room_num,  PublicMessage (0,s)));
              messages#we_11#set_text "";
(*self#insert_text (Printf.sprintf "> %s\n" s) *)
    
    initializer
      Okey.add messages#we_11
        ~mods: []
        GdkKeysyms._Return
        self#on_entry_return      
    
    method update_users =
      let list = match !selected_room with
          None ->  []
        | Some room ->
            let list = ref [] in
            List.iter (fun u ->
                try
                  let user_info = Hashtbl.find G.users u in
                  list := user_info :: !list
                with _ ->
                    Gui_com.send (GuiProto.GetUser_info u);
            ) room.room_users;
            !list
      in
      box_room_users#update_data list
    
    method append_message msg =
      match msg with
      | ServerMessage s -> 
(* try to get the user name to put some color: ????
Username of what ? ServerMessage is a message sent from the server, not from
  a user !!! *)
          let len = String.length s in
          if len > 0 then
            (
              let (user, mes) = 
                match s.[0] with
                  '<' ->
                    (
                      try 
                        let pos = String.index s '>' in
                        let u = String.sub s 1 (pos - 1) in
                        let mes = String.sub s (pos + 1) (len - pos - 1) in
                        (Some u, mes)
                      with
                        _ ->
                          (None, s)
                    )
                | _ ->
                    (None, s)
              in
              self#insert_text ?user (mes^"\n")
            )
          else
            ()
      
      | PublicMessage (user_num, s) ->
          (match !selected_room with None -> () | Some room ->
                add_room_user room user_num);
          let user = Hashtbl.find G.users user_num in
          self#insert_text ~user: user.user_name (s^"\n")
      | PrivateMessage (user_num, s) ->
          (match !selected_room with None -> () | Some room ->
                add_room_user room user_num);
          let user = Hashtbl.find G.users user_num in
          self#insert_text ~user: user.user_name ~priv: true (s^"\n")
    
    method rooms_pane = rooms_pane
    method selected_room = selected_room
    
    method select_room room =
      try
        begin
          match !selected_room with
            None -> ()
          | Some r when r == room -> raise Exit
          | _ -> self#clear
        end;
        selected_room := Some room;
        List.iter (fun msg -> self#append_message msg) (
          List.rev room.room_messages);
        self#update_users
      with Exit -> ()
    
    initializer
      room_pane#add1 box_room_users#coerce;
      room_pane#add2 messages#coerce;

end


class pane_rooms () =
  
  let pane = new pane_room () in
  let selected_room = pane#selected_room in
  let opened_rooms = new opened_rooms_box pane#select_room in
  let paused_rooms = new paused_rooms_box () in
  object (self)
    
    method opened_rooms = opened_rooms
    method paused_rooms = paused_rooms
    
    method clear = 
      opened_rooms#clear;
      paused_rooms#clear;
      pane#clear

(*
    method update_users room_users =
      let list = ref [] in
      List.iter (fun u ->
          try
            let user_info = Hashtbl.find G.users u in
            list := user_info :: !list
          with _ ->
              Gui_com.send (GuiProto.GetUser_info u);
      ) room_users;
      box_room_users#update_data !list
*)
    
    method  remove_room_user room_num user_num =
      try
        let (num, room) = try
            opened_rooms#find_room room_num 
          with _ -> paused_rooms#find_room room_num in
        if List.memq user_num room.room_users then begin
            room.room_users <- List2.removeq user_num room.room_users;
            match !selected_room with
            | Some r when r == room ->              
                pane#update_users
            | _ -> ()
          end
      with _ -> ()

      
    method  add_room_user room_num user_num =
      try
        let (num, room) = try
            opened_rooms#find_room room_num 
          with _ -> paused_rooms#find_room room_num in
        if not (List.memq user_num room.room_users) then begin
            room.room_users <- user_num :: room.room_users;
            match !selected_room with
            | Some r when r == room ->              
                pane#update_users
            | _ -> ()
          end
      with _ -> ()
    
    
    method add_room_message room_num msg =
      try
        let (num, room) = try
            opened_rooms#find_room room_num 
          with _ -> paused_rooms#find_room room_num in
        room.room_messages <- msg :: room.room_messages;
        match !selected_room with
        | Some r when r == room ->              
            pane#append_message msg
        | _ -> ()
      with e -> 
          Printf.printf "ROOM %d Exception %s" room_num (Printexc.to_string e);
          print_newline ();
          ()
    
    method room_info room =
      begin
        try
          let (num, old_room) = try
              opened_rooms#find_room room.room_num 
            with _ -> paused_rooms#find_room room.room_num in
          if old_room.room_state <> room.room_state then begin
              (match old_room.room_state with
                  RoomPaused -> paused_rooms#remove_room num old_room
                | RoomOpened -> 
                    opened_rooms#remove_room num old_room;
                    begin
                      match !selected_room with
                        Some r when r == room -> 
                          pane#clear; selected_room := None
                      | _ -> ()
                    end
                | _ -> assert false);
              match room.room_state with
              | RoomPaused -> paused_rooms#add_room room
              | RoomOpened -> opened_rooms#add_room room
              | RoomClosed -> ()
            end
        with Not_found ->
            match room.room_state with
            | RoomPaused -> paused_rooms#add_room room
            | RoomOpened -> opened_rooms#add_room room
            | RoomClosed -> ()
      end
      (* Maybe automatic selection is not that good ?:
      ;
      match opened_rooms#rooms with
        [room] -> opened_rooms#on_select room
      | _ -> () *)
        
    method coerce = pane#coerce

    method hpaned = pane#hpaned
      
    initializer
      pane#rooms_pane#add1 opened_rooms#coerce;
      pane#rooms_pane#add2 paused_rooms#coerce;
            
end

(* for now, no way to update users ? *)
let user_info user = ()

