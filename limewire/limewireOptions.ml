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

open CommonOptions
open Options

let cmd_basedir = Autoconf.current_dir (* will not work on Windows *)

let limewire_ini = create_options_file (
    Filename.concat file_basedir "limewire.ini")

let max_ultrapeers = define_option limewire_ini ["max_ultrapeers"]
    "Maximal number of ultrapeers connected"
  int_option 5

let _ = 
  option_hook max_ultrapeers 
    (fun _ ->
      if !!max_ultrapeers > 30 then max_ultrapeers =:= 30)
  
let client_port = define_option limewire_ini ["client_port"]
    "The port to bind the client to"
    int_option 6346

let redirectors = define_option limewire_ini ["redirectors"]
    "The hosts to connect to to get a list of peers"
    (list_option string_option)
  [
    "public.bearshare.net";
    "gnotella.fileflash.com";
    "gnutella-again.hostscache.com";
    "connect1.bearshare.net";
    "connect1.gnutellanet.com";
    "gnutella.hostscache.com";
    "connect2.gnutellanet.com";
    "connect3.gnutellanet.com"; 
    "router4.limewire.com";
  ]
(* (Ip.of_string "64.61.25.171")   *)
  
  
let commit_in_subdir = define_option limewire_ini ["commit_in_subdir"]
  "The subdirectory of temp/ where files should be moved to"
    string_option "LimeWire"
  

let max_known_ultrapeers = define_option limewire_ini ["max_known_ultrapeers"]
  "Maximal number of ultrapeers remembered"
    int_option 100

let max_known_peers = define_option limewire_ini ["max_known_peers"]
  "Maximal number of peers remembered"
  int_option 20

    
let server_connection_timeout = 
  define_option limewire_ini ["server_connection_timeout"] 
  "timeout when connecting to a server" float_option 10.
    
let verbose_clients = 
  define_option limewire_ini ["verbose_clients"] 
  "level of verbosity when communicating with clients" 
    int_option 0
    
let verbose_servers = 
  define_option limewire_ini ["verbose_servers"] 
    "level of verbosity when communicating with servers" int_option 0
  
let network_options_prefix = define_option limewire_ini
    ["options_prefix"] "The prefix which is appended to options names
    when they are used in the telnet/WEB interfaces"
    string_option "LW-"
  
let shortname o =
  Printf.sprintf "%s%s" !!network_options_prefix (shortname o)
  
let gui_limewire_options_panel = 
  define_option limewire_ini ["gui_limewire_options_panel"]
    "Which options are configurable in the GUI option panel, and in the
  limewire section. Last entry indicates the kind of widget used (B=Boolean,T=Text)"
    (list_option (tuple3_option (string_option, string_option, string_option)))
  [
    "Port", shortname client_port, "T";
    "Max Connected Ultrapeers", shortname max_ultrapeers, "T";
    "Max Known Ultrapeers", shortname max_known_ultrapeers, "T";
    "Max Known Peers", shortname max_known_peers, "T";    
    "Commit Downloads In Incoming Subdir", shortname commit_in_subdir, "T";
  ]
  