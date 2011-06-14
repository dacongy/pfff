(* Yoann Padioleau
 *
 * Copyright (C) 2002-2008 Yoann Padioleau
 * Copyright (C) 2011 Facebook
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License (GPL)
 * version 2 as published by the Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * file license.txt for more details.
 *)

open Common

module Flag = Flag_parsing_cpp
module Ast = Ast_cpp

module TH = Token_helpers_cpp
module LP = Lexer_parser_cpp
module Parser = Parser_cpp

open Parser_cpp
open Token_views_cpp

(*****************************************************************************)
(* Wrappers  *)
(*****************************************************************************)
let pr2, pr2_once = Common.mk_pr2_wrappers Flag_parsing_cpp.verbose_parsing

(*****************************************************************************)
(* Helpers  *)
(*****************************************************************************)

(* 
 * In the following, there are some harcoded names of types or macros
 * but they are not used by our heuristics! They are just here to
 * enable to detect false positive by printing only the typedef/macros
 * that we don't know yet. If we print everything, then we can easily
 * get lost with too much verbose tracing information. So those
 * functions "filter" some messages. So our heuristics are still good,
 * there is no more (or not that much) hardcoded linux stuff.
 *)
let msg_gen cond is_known printer s = 
  if cond
  then
    if not (!Flag.filter_msg)
    then printer s
    else
      if not (is_known s)
      then printer s

let pos ii = Ast.string_of_info ii

(*****************************************************************************)
(* Some debugging functions  *)
(*****************************************************************************)

let pr2_pp s = 
  if !Flag.debug_pp
  then Common.pr2_once ("PP-" ^ s)

let pr2_cplusplus s = 
  if !Flag.debug_cplusplus
  then Common.pr2_once ("C++-" ^ s)


let msg_change_tok tok =
  match tok with

  | TIdent_Define (s, ii) ->
      ()
  | TOPar_Define (ii) ->
      ()
  | TCommentNewline_DefineEndOfMacro _ ->
      ()

  | TInclude_Start ii -> 
      ()
  | TInclude_Filename ii -> 
      ()

  | TIdent_Typedef (s, ii) ->
      (* todo? also do LP.add_typedef_root s ??? *)
      s +> msg_gen (!Flag.debug_typedef) (fun s ->
        match s with
        | "u_char"   | "u_short"  | "u_int"  | "u_long"
        | "u8" | "u16" | "u32" | "u64" 
        | "s8"  | "s16" | "s32" | "s64" 
        | "__u8" | "__u16" | "__u32"  | "__u64"  
            -> true
        | "acpi_handle" | "acpi_status" -> true
        | "FILE" | "DIR"                -> true
        | s when s =~ ".*_t$"           -> true
        | _                             -> false 
      ) 
      (fun s -> pr2_pp (spf "TYPEDEF: promoting %s at %s " s (pos ii)))

  (* cppext: *)

  | TComment_Cpp (directive, ii) ->
      let s = Ast.str_of_info ii in
      (match directive, s with
      | Token_cpp.CppMacro, _ ->
          pr2_pp (spf "MACRO: commented at %s" (pos ii))

      | Token_cpp.CppDirective, _ when s =~ "#define.*" ->
          pr2_pp (spf "DEFINE: commented at %s" (pos ii));
      | Token_cpp.CppDirective, _ when s =~ "#include.*" ->
          pr2_pp (spf "INCLUDE: commented at %s" (pos ii));
      | Token_cpp.CppDirective, _ when s =~ "#if.*" ->
          pr2_pp (spf "IFDEF: commented at %s" (pos ii));
      | Token_cpp.CppDirective, _ when s =~ "#undef.*" -> 
          pr2_pp (spf "UNDEF: commented at %s" (pos ii));
      | Token_cpp.CppDirective, _ ->
          pr2_pp (spf "OTHER: commented directive at %s" (pos ii));
      | _ ->
          (* todo? *)
          ()
      )

  | TOBrace_DefineInit ii ->
      pr2_pp (spf "DEFINE: initializer at %s" (pos ii))

  | TIdent_MacroString ii ->
      let s = Ast.str_of_info ii in
      s +> msg_gen (!Flag.debug_pp) (fun s -> 
        match s with 
        | "REVISION" | "UTS_RELEASE" | "SIZE_STR" | "DMA_STR"
            -> true
            (* s when s =~ ".*STR.*" -> true  *) 
        | _ -> false
      )
      (fun s -> pr2_pp (spf "MACRO: string-macro %s at %s " s (pos ii)))

  | TIdent_MacroStmt ii ->
      pr2_pp (spf "MACRO: stmt-macro at %s" (pos ii));

  | TIdent_MacroDecl (s, ii) ->
      s +> msg_gen (!Flag.debug_pp) (fun s -> 
        match s with 
        | "DECLARE_MUTEX" | "DECLARE_COMPLETION"  | "DECLARE_RWSEM"
        | "DECLARE_WAITQUEUE" | "DECLARE_WAIT_QUEUE_HEAD" 
        | "DEFINE_SPINLOCK" | "DEFINE_TIMER"
        | "DEVICE_ATTR" | "CLASS_DEVICE_ATTR" | "DRIVER_ATTR"
        | "SENSOR_DEVICE_ATTR"
        | "LIST_HEAD"
        | "DECLARE_WORK"  | "DECLARE_TASKLET"
        | "PORT_ATTR_RO" | "PORT_PMA_ATTR"
        | "DECLARE_BITMAP"
          -> true
            (*
              | s when s =~ "^DECLARE_.*" -> true
              | s when s =~ ".*_ATTR$" -> true
              | s when s =~ "^DEFINE_.*" -> true
              | s when s =~ "NS_DECL.*" -> true
            *)
        | _ -> false
      )
      (fun s -> pr2_pp (spf "MACRO: macro-declare at %s" (pos ii)))

  | Tconst_MacroDeclConst ii ->
      pr2_pp (spf "MACRO: retag const at %s" (pos ii))

  | TCPar_EOL ii ->
      pr2_pp (spf "MISC: retagging ) %s" (pos ii))

  (* c++ext: *)
  | TOPar_CplusplusInit ii ->
      pr2_cplusplus (spf "constructor initializer at %s" (pos ii))

  | TOCro_new ii | TCCro_new ii ->
      pr2_cplusplus (spf "new [] at %s" (pos ii))

  | TInf_Template ii | TSup_Template ii ->
      pr2_cplusplus (spf "<> at %s" (pos ii))

  | _ -> raise Todo


let msg_foreach s = 
  pr2_pp ("MACRO: found foreach: " ^ s)

let msg_debug_macro s = 
  pr2_pp ("MACRO: found debug-macro: " ^ s)

let msg_macro_higher_order s = 
  msg_gen (!Flag.debug_pp)
    (fun s -> 
      (match s with 
      | "DBGINFO"
      | "DBGPX"
      | "DFLOW"
        -> true
      | _ -> false
      )
    )
    (fun s -> pr2_pp ("MACRO: found higher ordre macro : " ^ s))
    s

let msg_classname s = 
  pr2_cplusplus ("CLASSNAME: found " ^ s)

let msg_templatename s = 
  pr2_cplusplus ("TEMPLATENAME: found " ^ s)

let msg_constructorname s = 
  pr2_cplusplus ("CONSTRUCTORNAME: found " ^ s)

(* todo: more msg_xxx from parsing_c/ *)  

let change_tok extended_tok tok =
  msg_change_tok tok;

  (* otherwise parse_c will be lost if don't find a EOF token 
   * why? because paren detection had a pb because of
   * some ifdef-exp?
   *)
  if TH.is_eof extended_tok.tok
  then pr2 "PB: wierd, I try to tag an EOF token as something else"
  else extended_tok.tok <- tok

let fresh_tok tok =
  msg_change_tok tok;
  tok

(* normally the caller have first filtered the set of tokens to have
 * a clearer "view" to work on
 *)
let set_as_comment cppkind x = 
  assert(not (TH.is_real_comment x.tok));
  change_tok x (TComment_Cpp (cppkind, TH.info_of_tok x.tok))

(*****************************************************************************)
(* The regexp and basic view definitions *)
(*****************************************************************************)

(*
val regexp_macro: Str.regexp
val regexp_annot: Str.regexp
val regexp_declare: Str.regexp
val regexp_foreach: Str.regexp
val regexp_typedef: Str.regexp
*)

(* opti: better to built then once and for all, especially regexp_foreach *)

let regexp_macro =  Str.regexp
  "^[A-Z_][A-Z_0-9]*$"

(* linuxext: *)
let regexp_annot =  Str.regexp
  "^__.*$"

(* linuxext: *)
let regexp_declare =  Str.regexp
  ".*DECLARE.*"

(* linuxext: *)
let regexp_foreach = Str.regexp_case_fold 
  ".*\\(for_?each\\|for_?all\\|iterate\\|loop\\|walk\\|scan\\|each\\|for\\)"

let regexp_typedef = Str.regexp
  ".*_t$"

let false_typedef = [
  "printk";
  ]

(* firefoxext: *)
let regexp_ns_decl_like = Str.regexp
  ("\\(" ^
   "NS_DECL_\\|NS_DECLARE_\\|NS_IMPL_\\|" ^ 
   "NS_IMPLEMENT_\\|NS_INTERFACE_\\|NS_FORWARD_\\|NS_HTML_\\|" ^
   "NS_DISPLAY_\\|NS_IMPL_\\|" ^
   "TX_DECL_\\|DOM_CLASSINFO_\\|NS_CLASSINFO_\\|IMPL_INTERNAL_\\|" ^
   "ON_\\|EVT_\\|NS_UCONV_\\|NS_GENERIC_\\|NS_COM_" ^
   "\\).*")


let ok_typedef s = 
  not (List.mem s false_typedef)

let not_annot s = 
  not (s ==~ regexp_annot)
