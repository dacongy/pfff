(*s: coverage_static_php.ml *)
(* Yoann Padioleau
 *
 * Copyright (C) 2010 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)

open Common

open Ast_php

module Ast = Ast_php
module V = Visitor_php

module Db = Database_php
module CG = Callgraph_php 

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(* Abstract away a little the way we determine whether a function is
 * covered by a unit test.
 * 
 * For the static case, we need to look at all the files, decide whether
 * they contain unit testing code (for instance because they are in a
 * __tests__/ or scripts/unittest/test/ directory), and then statically
 * look at all the function calls inside those testing code. 
 * 
 * todo? could have a field in Database_php that say whether a file is 
 * a unit test file.
 * todo? could have a statically_covered field in Database_php, that cache
 * this information.
 * 
 *)
let (mk_is_covered_by_test: 
       is_test_file:(Common.filename -> bool) ->
       Database_php.database -> (Entity_php.id -> bool)) =
 fun ~is_test_file db ->

   let h_covered_functions = Hashtbl.create 101 in

  (* let's iterate over all functions and look if its callers
   * (could be a function or method) are in a test file.
   *)
   Db.functions_in_db db +> List.iter (fun (s, ids) ->
     ids +> List.iter (fun id -> 
       let _file = Db.filename_of_id id db in
       
       try (
         let callers = Db.callers_of_id id db in
         callers +> List.iter (fun caller -> 
           let idcaller = CG.id_of_callerinfo caller in
           let file_caller = Db.filename_of_id idcaller db in
           if is_test_file file_caller
           then begin
             Hashtbl.replace h_covered_functions id true;
           end
         )
       )
       with Not_found -> ()
     )
   );

  (fun id ->
    Hashtbl.mem h_covered_functions id
  )

(*e: coverage_static_php.ml *)
