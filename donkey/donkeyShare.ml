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

open CommonFile
open CommonShared
open CommonTypes
open Options
open Unix
open BasicSocket
open TcpBufferedSocket
open DonkeyMftp
open DonkeyImport
open DonkeyProtoCom
open DonkeyTypes
open DonkeyOptions
open CommonOptions
open DonkeyComplexOptions
open DonkeyGlobals
  
let must_share_file file =
  match file.file_shared with
  | Some _ -> ()
  | None ->
      new_shared := file :: !new_shared;
      let impl = {
          impl_shared_update = 1;
          impl_shared_fullname = file_disk_name file;
          impl_shared_codedname = file_best_name file;
          impl_shared_size = file_size file;
          impl_shared_num = 0;
          impl_shared_uploaded = Int64.zero;
          impl_shared_ops = shared_ops;
          impl_shared_val = file;
          impl_shared_requests = 0;
        } in
      update_shared_num impl;
      file.file_shared <- Some impl

let new_file_to_share sh =
  try
(* How do we compute the total MD4 of the file ? *)
    
    let md4s = List.rev sh.sh_md4s in
    let md4 = match md4s with
        [md4] -> md4
      | [] -> Printf.printf "No md4 for %s" sh.sh_name;
          print_newline ();
          raise Not_found
      | _ -> 
          let len = List.length md4s in
          let s = String.create (len * 16) in
          let rec iter list i =
            match list with
              [] -> ()
            | md4 :: tail ->
                let md4 = Md4.direct_to_string md4 in
                String.blit md4 0 s i 16;
                iter tail (i+16)
          in
          iter md4s 0;
          Md4.string s
    in
    
    let file = new_file FileShared sh.sh_name md4 sh.sh_size false in
    must_share_file file;
    file.file_md4s <- md4s;
    file.file_filenames <- file.file_filenames @ [Filename.basename sh.sh_name]; 
    file.file_chunks <- Array.make file.file_nchunks PresentVerified;
    file.file_absent_chunks <- [];
    file.file_all_chunks <- String.make file.file_nchunks '1';
    (try 
        file.file_format <- CommonMultimedia.get_info 
          (file_disk_name file)
      with _ -> ());
    Printf.printf "Sharing %s" sh.sh_name;
    print_newline ();
  with e ->
      Printf.printf "Exception %s while sharing %s" (Printexc.to_string e)
      sh.sh_name; print_newline () 
      
  
let all_shared () =  
  let shared_files = ref [] in
  Hashtbl.iter (fun md4 file ->
      match  file.file_shared with
        None -> ()
      | Some _ ->  shared_files := file :: !shared_files
  ) files_by_md4;
  !shared_files

(*  Check whether new files are shared, and send them to connected servers.
Do it only once per 5 minutes to prevent sending to many times all files.
  Should I only do it for master servers, no ?
  *)
let send_new_shared () =
  if !new_shared != [] then
    begin
      new_shared := [];
      let socks = ref [] in
      let list = all_shared () in
      List.iter (fun s ->
          if s.server_master then
            match s.server_sock with
              None -> ()
            | Some sock ->
                direct_server_send_share sock list) (connected_servers ());
    end

(*   Compute (at most) one MD4 chunk if needed. *)
let check_shared_files () =  
  match !shared_files with
    [] -> ()  
  | sh :: files ->
      try
        if not (Sys.file_exists sh.shared_name) then begin
            Printf.printf "Shared file doesn't exist"; print_newline ();
            raise Not_found;
          end;
        if Unix32.getsize32 sh.shared_name <> sh.shared_size then begin
            Printf.printf "Bad shared file size" ; print_newline ();
            raise Not_found;
          end;
        let end_pos = Int32.add sh.shared_pos block_size in
        let end_pos = if end_pos > sh.shared_size then sh.shared_size
          else end_pos in
        let len = Int32.sub end_pos sh.shared_pos in
        
        Printf.printf "check_shared_files"; print_newline ();
        let new_md4 = Md4.digest_subfile (sh.shared_fd) sh.shared_pos len in
        
        sh.shared_list <- new_md4 :: sh.shared_list;
        sh.shared_pos <- end_pos;
        if end_pos = sh.shared_size then begin
            shared_files := files;
            let s = {
                sh_name = sh.shared_name;
                sh_size = sh.shared_size;
                sh_md4s = sh.shared_list;
                sh_mtime = (let st = Unix.stat sh.shared_name in
                  st.Unix.st_mtime);
              } in
            Printf.printf "NEW SHARED FILE %s" sh.shared_name; 
            print_newline ();
            Hashtbl.add shared_files_info sh.shared_name s;
            known_shared_files =:= s :: !!known_shared_files;
            new_file_to_share s;
            shared_remove  sh.shared_shared;
            if !shared_files = [] then begin
(*                  Printf.printf "Saving shared files"; print_newline (); *)
                save shared_files_ini
              end                
          end
      with e ->
          Printf.printf "Exception %s prevents sharing"
            (Printexc.to_string e);
          print_newline ();
          shared_files := files;
          if !shared_files = [] then begin
(*                Printf.printf "Saving shared files"; print_newline (); *)
              save shared_files_ini
            end                
            
let local_dirname = Sys.getcwd ()
  
        
let _ =
  network.op_network_share <- (fun fullname codedname size ->       
      Printf.printf "FULLNAME %s" fullname; print_newline ();
      let codedname = Filename.basename codedname in
      Printf.printf "CODEDNAME %s" codedname; print_newline ();
      try
        Printf.printf "Searching %s" fullname; print_newline ();
        let s = Hashtbl.find shared_files_info fullname in
        let mtime = (Unix.stat fullname).Unix.st_mtime in
        if s.sh_mtime = mtime && s.sh_size = size then begin
            Printf.printf "USING OLD MD4s for %s" fullname;
            print_newline (); 
            new_file_to_share s
          end else begin
            Printf.printf "Shared file %s has been modified" fullname;
            print_newline ();
            Hashtbl.remove shared_files_info fullname;
            known_shared_files =:= List2.removeq s !!known_shared_files
          end
      with Not_found ->
          Printf.printf "No info on %s" fullname; print_newline (); 

          let rec impl = {
              impl_shared_update = 1;
              impl_shared_fullname = fullname;
              impl_shared_codedname = codedname;
              impl_shared_size = size;
              impl_shared_num = 0;
              impl_shared_uploaded = Int64.zero;
              impl_shared_ops = pre_shared_ops;
              impl_shared_val = pre_shared;
              impl_shared_requests = 0;
            } and
            pre_shared = {
              shared_shared = impl;
              shared_name = fullname;              
              shared_size = size;
              shared_list = [];
              shared_pos = Int32.zero;
              shared_fd = Unix32.create fullname [O_RDONLY] 0o444;
            } in
          update_shared_num impl;  
          shared_files := pre_shared :: !shared_files;
          
)
  
let remember_shared_info file new_name =
  if file.file_md4s <> [] then
    try
      let disk_name = file_disk_name file in
      let mtime = (Unix.stat disk_name).Unix.st_mtime in
      
      Printf.printf "Remember %s" new_name; print_newline ();
      Hashtbl.add shared_files_info new_name {
        sh_name = new_name;
        sh_size = file_size file;
        sh_mtime = mtime;
        sh_md4s = file.file_md4s;
      }
    with e ->
        Printf.printf "Exception %s in remember_shared_info"
          (Printexc.to_string e);
        print_newline ()
        