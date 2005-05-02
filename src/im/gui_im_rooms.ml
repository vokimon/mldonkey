open ImTypes
open Gui_columns
open ImIdentity
  
class box () =
  let vbox = GPack.vbox ~homogeneous:false () in
  let wtool =
    GButton.toolbar ~orientation:`HORIZONTAL ~style:`BOTH ~space_size:2
      ~space_style:`LINE ~tooltips:true ~button_relief:`NONE
      ~packing:(vbox#pack ~expand:false ~fill:true ~padding:2) ()
  in
  object
    val vbox = vbox
    val wtool = wtool
    method vbox = vbox
    method wtool = wtool
    method coerce = vbox#coerce
  end

      
(** The different columns which can be displayed for a identity/location/friend. *)
type identity_column = 
|  Col_identity_name

let identity_column_strings = [
    Col_identity_name, "Name" ;
] 

module IdentityCols = Make(struct 
      type column = identity_column 
      let kind = "Identity"
      let column_strings = identity_column_strings
    end)


let identity_columns = [ Col_identity_name ]
  
class identity_box () =
  let titles = List.map IdentityCols.string_of_column identity_columns in 
  object (self)
    inherit [ImTypes.identity] Gpattern.plist `EXTENDED titles true 
    (fun id -> identity_num id) as pl
      inherit box () as box
    
    val mutable columns = identity_columns
    method set_columns l =
      columns <- l;
      self#set_titles (List.map IdentityCols.string_of_column columns);
      self#update
    
    
    method compare_by_col col f1 f2 =
      match col with
        Col_identity_name -> compare (identity_name f1) (identity_name f2)
          
    method compare f1 f2 =
      let abs = if current_sort >= 0 then current_sort else - current_sort in
      let col = 
	try List.nth columns (abs - 1) 
	with _ -> Col_identity_name
      in
      let res = self#compare_by_col col f1 f2 in
      res * current_sort

    method content_by_col f col =
      match col with
        Col_identity_name -> identity_name f

    method content f =
      let strings = List.map 
	  (fun col -> Gpattern.String (self#content_by_col f col))
	  columns 
      in
      let col_opt = Some `BLACK      in
      (strings, col_opt)
          
    method menu = []
      (*
      match self#selection with
	[] -> []
      |	_ -> [ 
            `I (gettext M.add_to_friends, self#add_to_friends);
            `I (gettext M.browse_files, self#browse_files)
          ]
*)
      
    method set_tb_style = wtool#set_style

    method find_identity num = self#find num

      
    initializer
      box#vbox#pack ~expand: true pl#box ;
      
      (*
      ignore
	(wtool#insert_button 
	   ~text: (gettext M.add_to_friends)
	   ~tooltip: (gettext M.add_to_friends)
	   ~icon: (Gui_icons.pixmap M.o_xpm_add_to_friends)#coerce
	   ~callback: self#add_to_friends
	   ()
);
  *)
  end

(*
class box tb_style () =
  object(self)
    inherit Gui_rooms_base.box tb_style () 
    
    method set_tb_style (tb_style : Gtk.Tags.toolbar_style) = ()
end

class rooms_box columns () =
  
  let titles = List.map Gui_columns.Room.string_of_column columns in 
  object (self)
    inherit [GuiTypes.room_info] Gpattern.plist `SINGLE titles true (fun r -> r.room_num) as pl
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
    
    method find_room num = self#find num

    method add_room room = self#add_item room
    
    method remove_room row room = self#remove_item row room
    
    method set_tb_style = wtool#set_style
    
    initializer
      box#vbox#pack ~expand: true pl#box ;

end

class box_users room =
  
  object (self)
    
    inherit Gui_users.box_users ()
    
    initializer
      
      ignore
        (wtool#insert_button 
          ~text: (gettext M.close_room)
          ~tooltip: (gettext M.close_room)
          ~icon: (Gui_options.pixmap M.o_xpm_close_room)#coerce
          ~callback: (fun _ ->  
            Gui_com.send (GuiProto.SetRoomState (
                room.room_num, RoomClosed)))
        ()
      );

end

class opened_rooms_box on_select =
  object (self)
    
    inherit rooms_box !!O.rooms_columns  () as box_rooms
    
    method add_room room =
      box_rooms#add_room room;
      let w = box_rooms#wlist in
      w#select (w#rows - 1) 0

(*     method rooms = data *)
    method on_select room = on_select room
end

class paused_rooms_box () =
  object (self)

    inherit rooms_box !!O.rooms_columns  () as box_rooms

  
    method on_double_click room = 
      Gui_com.send (GuiProto.SetRoomState (room.room_num, RoomOpened))      

end

let add_room_user room user_num =
  lprintf "ADD ROOM USER"; lprint_newline ();
  if not (List.memq user_num room.room_users) then begin
      room.room_users <- user_num :: room.room_users;
      lprintf "Should have added user"; lprint_newline ();
    end
    
let insert_text (messages: box) ?user ?(priv=false) s =
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

let update_users r (users : box_users) =
  let list = ref [] in
  List.iter (fun u ->
      try
        let user_info = Hashtbl.find G.users u in
        list := user_info :: !list
      with _ ->
          Gui_com.send (GuiProto.GetUser_info u);
  ) r.room_users;
  users#reset_data !list

let append_message r (messages:box) msg =
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
          insert_text messages ?user (mes^"\n")
        )
      else
        ()      
  | PublicMessage (user_num, s) ->
      add_room_user r user_num;
      let user = Hashtbl.find G.users user_num in
      insert_text messages ~user: user.user_name (s^"\n")
  | PrivateMessage (user_num, s) ->
      add_room_user r user_num;
      let user = Hashtbl.find G.users user_num in
      insert_text messages ~user: user.user_name ~priv: true (s^"\n")
*)

(*
class pane_rooms () =
  
  let select = ref (fun room -> ()) in
  let (widgets: (int, box_users * box) Hashtbl.t) = Hashtbl.create 13 in
  let opened_rooms = new opened_rooms_box (fun room -> !select room) in
  let paused_rooms = new paused_rooms_box () in
  
  object(self)
    inherit Gui_rooms_base.box2 ()
    
    method clear_widgets room = 
      try
        let (users, messages) = Hashtbl.find widgets room.room_num in
        users#coerce#misc#unmap ();
        messages#coerce#misc#unmap ();
        users#coerce#misc#unparent ();
        messages#coerce#misc#unparent ();
        Hashtbl.remove widgets room.room_num
      with _ -> ()
    
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
                    self#clear_widgets room;
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
    
    
    method add_room_message room_num msg =
      try
        let (num, room) = try
            opened_rooms#find_room room_num 
          with _ -> paused_rooms#find_room room_num in
        room.room_messages <- msg :: room.room_messages;
        try
          let (users, messages) = Hashtbl.find widgets room_num in
          append_message room messages msg
        with _ -> ()
      with e -> 
          lprintf "ROOM %d Exception %s" room_num (Printexc2.to_string e);
          lprint_newline ();
          ()
    
    
    
    method hpaned = hpaned
    
    method clear = 
      opened_rooms#clear;
      paused_rooms#clear;
      opened_rooms#iter self#clear_widgets
    
    method  remove_room_user room_num user_num =
      try
        let (num, room) = try
            opened_rooms#find_room room_num 
          with _ -> paused_rooms#find_room room_num in
        if List.memq user_num room.room_users then begin
            room.room_users <- List2.removeq user_num room.room_users;
            try
              let (users, messages) = Hashtbl.find widgets room_num in
              update_users room users
            with _ -> ()
          end                
      with _ -> ()
    
    
    method  add_room_user room_num user_num =
      lprintf "add romm user"; lprint_newline ();
      try
        let (num, room) = try
            opened_rooms#find_room room_num 
          with _ -> paused_rooms#find_room room_num in
        if not (List.memq user_num room.room_users) then begin
            room.room_users <- user_num :: room.room_users;
            try
              let (users, messages) = Hashtbl.find widgets room_num in
              lprintf "update_users"; lprint_newline ();
              update_users room users
            with _ -> ()
          end
      with _ -> ()
    
    initializer
      rooms_pane#add1 opened_rooms#coerce;
      rooms_pane#add2 paused_rooms#coerce;
      select := (fun room ->      
          let (users, messages) = try Hashtbl.find widgets room.room_num 
            with _ ->
                let users = new box_users room in
                let messages = new box () () in
                let  on_entry_return () =
                  match messages#we_11#text with
                    "" -> ()
                  |	s ->
                      Gui_com.send
                        (GuiProto.SendMessage (room.room_num,  
                          PublicMessage (0,s)));
                      messages#we_11#set_text "";
(*self#insert_text (Printf.sprintf "> %s\n" s) *)
                in          
                Okey.add messages#we_11 ~mods: [] GdkKeysyms._Return
                  on_entry_return;
                Hashtbl.add widgets room.room_num (users, messages);
                users, messages
          in
          room_pane#add1 users#coerce;
          room_pane#add2 messages#coerce;
          update_users room users
      )      
end

(* for now, no way to update users ? *)
let user_info user = ()

  *)

let room_num room = 1

class room_window (room: room) =
  
  object (self)

    inherit Gui_im_base.room_tab ()
    
    method update_room = ()
end