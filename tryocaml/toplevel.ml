(* Js_of_ocaml toplevel
 * http://www.ocsigen.org/js_of_ocaml/
 * (C) 2011 Jérôme Vouillon Laboratoire PPS - CNRS Université Paris Diderot
 * (C) 2011 Cagdas Bozman - OCamlPro SAS
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

let split_primitives p =
  let len = String.length p in
  let rec split beg cur =
    if cur >= len then []
    else if p.[cur] = '\000' then
      String.sub p beg (cur - beg) :: split (cur + 1) (cur + 1)
    else
      split beg (cur + 1) in
  Array.of_list(split 0 0)

(****)

external global_data : unit -> Obj.t array = "caml_get_global_data"

let g = global_data ()

let _ =
  let toc = Obj.magic (Array.unsafe_get g (-2)) in
  let prims = split_primitives (List.assoc "PRIM" toc) in

  let compile s =
    let output_program = Driver.from_string prims s in
    let b = Buffer.create 100 in
    output_program (Pretty_print.to_buffer b);
    Buffer.contents b
  in
  Array.unsafe_set g (-3) (Obj.repr compile); (*XXX HACK!*)

module Html = Dom_html

let s = ""

let doc = Html.document
let button_type = Js.string "button"
let button txt action =
  let b = Dom_html.createInput ~_type:button_type doc in
  b##value <- Js.string txt;
  b##onclick <- Dom_html.handler (fun _ -> action (); Js._true);
  b

let exec ppf s =
  let lb = Lexing.from_string s in
  try
    List.iter
      (fun phr ->
        if not (Toploop.execute_phrase false ppf phr) then raise Exit)
      (!Toploop.parse_use_file lb)
  with
    | Exit -> ()
    | x    -> Errors.report_error ppf x

let start ppf =
  Format.fprintf ppf "        Welcome to TryOCaml (v. %s)@.@." Sys.ocaml_version;
  Toploop.initialize_toplevel_env ();
  Toploop.input_name := "";
  exec ppf "open Tutorial";
  exec ppf "#install_printer Toploop.print_hashtbl";
  exec ppf "#install_printer Toploop.print_queue";
  exec ppf "#install_printer Toploop.print_stack";
  exec ppf "#install_printer Toploop.print_lazy";
  ()

let at_bol = ref true
let consume_nl = ref false

let input = ref []
let output = ref []

let rec refill_lexbuf s p ppf buffer len =
  match !input with
    | '\000' :: tail ->
      input := tail;
      refill_lexbuf s p ppf buffer len
    | c :: tail ->
      input := tail;
      output := c :: !output;
      buffer.[0] <- c;
      1
    | [] ->
      if !consume_nl then begin
        let l = String.length s in
        if (!p < l && s.[!p] = '\n') then
          incr p
        else if (!p + 1 < l && s.[!p] = '\r' && s.[!p + 1] = '\n') then
          p := !p + 2;
        consume_nl := false
      end;
      if !p = String.length s then begin
        output := '\000' :: !output;
        0
      end else begin
        let c = s.[!p] in
        incr p;
        buffer.[0] <- c;
        if !at_bol then Format.fprintf ppf "# ";
        at_bol := (c = '\n');
        if c = '\n' then
          Format.fprintf ppf "@."
        else
          Format.fprintf ppf "%c" c;
        output := c :: !output;
        1
      end

let ensure_at_bol ppf =
  if not !at_bol then begin
    Format.fprintf ppf "@.";
    consume_nl := true; at_bol := true
  end

let update_lesson_text () =
  if  !Tutorial.this_lesson <> 0 then
  try
    let container =
      Js.Opt.get (doc##getElementById (Js.string "lesson-text"))
        (fun () -> assert false)
    in
    container##innerHTML <- Js.string !Tutorial.this_step_html
  with _ -> ()

let update_lesson_number () =
  if  !Tutorial.this_lesson <> 0 then
    try
    let container =
      Js.Opt.get (doc##getElementById (Js.string "lesson-number"))
        (fun () -> assert false)
    in
    container##innerHTML <- Js.string
      (Printf.sprintf "<span class=\"lesson\">Lesson %d</span>" !Tutorial.this_lesson)
  with _ -> ()

let update_lesson_step_number () =
  if  !Tutorial.this_lesson <> 0 then
  try
    let container =
      Js.Opt.get (doc##getElementById (Js.string "lesson-step"))
        (fun () -> assert false)
    in
    container##innerHTML <- Js.string
      (Printf.sprintf "<span class=\"step\">Step %d</span>" !Tutorial.this_step)
  with _ -> ()

let update_prompt prompt =
  try
    let container =
      Js.Opt.get (doc##getElementById (Js.string "sharp"))
        (fun () -> assert false)
    in
    container##innerHTML <- Js.string prompt
  with _ -> ()

let extract_escaped_and_kill html i =
  let len = String.length html in
  let rec iter html i len =
    if i = len then i else
      match html.[i] with
          ';' -> i+1
        | _ -> iter html (i+1) len
  in
  let end_pos = iter html (i+1) len in
  let s = String.sub html i (end_pos - i) in
  for j = i to end_pos - 1 do
    html.[j] <- '\000'
  done;
  s

let text_of_html html =
  let b = Buffer.create (String.length html) in
  for i = 0 to String.length html - 1 do
    match html.[i] with
        '&' ->
          begin
            match extract_escaped_and_kill html i with
              | "&gt;" -> Buffer.add_char b '>'
              | "&lt;" -> Buffer.add_char b '<'
              | "&amp;" -> Buffer.add_char b '&'
              | _ -> ()
          end
      | '\000' -> ()
      | c -> Buffer.add_char b c
  done;
  Buffer.contents b


let update_debug_message =
  let b = Buffer.create 100 in
  Tutorial.debug_fun := (fun s -> Buffer.add_string b s; Buffer.add_string  b "<br/>");
  function () ->
    let s = Buffer.contents b in
    Buffer.clear b;
    try
      let container =
        Js.Opt.get (doc##getElementById (Js.string "lesson-debug"))
          (fun () -> assert false)
      in
      if s = "" then
        container##innerHTML <- Js.string ""
      else
        container##innerHTML <- Js.string
          (Printf.sprintf
             "<div class=\"alert-message block-message warning\">%s</div>" s)
    with _ -> ()

exception End_of_input

let string_of_char_list list =
  let len = List.length list in
  let s = String.create len in
  let rec iter s i list =
    match list with
        [] -> s
      | c :: tail ->
        s.[i] <- c;
        iter s (i+1) tail
  in
  iter s 0 list

let loop s ppf buffer =
  let s =
    if !Tutorial.use_multiline then begin
      input := List.rev ('\n' :: !output);
      output := [];
      s
    end else begin
      let need_terminator = ref true in
      for i = 0 to String.length s - 2 do
        if s.[i] = ';' && s.[i+1] = ';' then need_terminator := false;
      done;
      output := [];
      if !need_terminator then s ^ ";;" else s
    end
  in
  let lb = Lexing.from_function (refill_lexbuf s (ref 0) ppf) in
  begin try
    while true do
      begin
      try
        let phr = try
                    !Toploop.parse_toplevel_phrase lb
          with End_of_file -> raise End_of_input
        in
        let input = string_of_char_list (List.rev !output) in
        if !Tutorial.use_multiline then begin
          match !output with
              ';' :: ';' :: _ -> output := []
            | _ -> assert false
        end else output := [];
        ensure_at_bol ppf;
        Buffer.clear buffer;
        Tutorial.print_debug s;
        ignore (Toploop.execute_phrase true ppf phr);
        let res = Buffer.contents buffer in
        Tutorial.check_step ppf input res;
        update_lesson_text ();
        update_lesson_number ();
        update_lesson_step_number ();
      with
          End_of_input ->
            ensure_at_bol ppf;
            raise End_of_input
        | x ->
          let do_report_error =
            if !Tutorial.use_multiline then
              match !output with
                  '\000' :: _ -> false
                | _ -> true
            else true
          in
          if do_report_error then begin
            output := [];
            ensure_at_bol ppf;
            Errors.report_error ppf x
          end
      end;
      update_debug_message ();
    done
    with End_of_input ->
      match !output with
          [] | [ '\000' ] ->
            output := []; update_prompt "#"
        | _ ->
          let s = string_of_char_list (List.rev !output) in
          let len = String.length s in
          let s = if len >= 5 then String.sub s 0 5 else s in
          update_prompt (Printf.sprintf "[%s]> " s)
  end

let _ =
  Tutorial.message_fun := (fun s ->
    if  !Tutorial.this_lesson <> 0 then
    try
      let container =
        Js.Opt.get (doc##getElementById (Js.string "lesson-message"))
          (fun () -> assert false)
      in
      container##innerHTML <- Js.string
        (Printf.sprintf
           "<div class=\"alert-message block-message success\">%s</div>" s)
    with _ -> ()
  )

let run _ =
  let top =
    Js.Opt.get (doc##getElementById (Js.string "toplevel"))
      (fun () -> assert false)
  in
  let output_area =
    Js.Opt.get (doc##getElementById (Js.string "output"))
      (fun () -> assert false)
  in
  let buffer = Buffer.create 1000 in

  let ppf =
    let b = Buffer.create 80 in
    Format.make_formatter
      (fun s i l ->
        Buffer.add_substring buffer s i l;
        Buffer.add_substring b s i l)
      (fun _ ->
        Dom.appendChild output_area
          (doc##createTextNode(Js.string (Buffer.contents b)));
        Buffer.clear b)
  in

  let textbox = Html.createTextarea doc in
  textbox##value <- Js.string "";
  textbox##id <- Js.string "console";
  Dom.appendChild top textbox;
  textbox##focus();
  textbox##select();
  let container =
    Js.Opt.get (doc##getElementById (Js.string "toplevel-container"))
      (fun () -> assert false)
  in
  let history = ref [] in
  let history_bckwrd = ref [] in
  let history_frwrd = ref [] in

  let rec make_code_clickable () =
    let textbox =
      Js.Opt.get (doc##getElementById(Js.string "console")) (fun () -> assert false) in
    let textbox = match Js.Opt.to_option (Html.CoerceTo.textarea textbox) with
      | None   -> assert false
      | Some t -> t in
    let codes = Dom.list_of_nodeList (doc##getElementsByTagName(Js.string "code")) in
    List.iter (fun code ->
      let html =  code##innerHTML in
      let txt = text_of_html (Js.to_string html) in
      code##title <- Js.string "Click here to execute this code";
      code##onclick <- Html.handler (fun _ ->
        textbox##value <- Js.string ( txt ^ ";;" );
        execute ();
        Js._true)
    ) codes

  and execute () =
    let s = Js.to_string textbox##value in
    if s <> "" then history := Js.string s :: !history;
    history_bckwrd := !history;
    history_frwrd := [];
    textbox##value <- Js.string "";
    loop s ppf buffer;
    make_code_clickable ();
    textbox##focus();
    container##scrollTop <- container##scrollHeight;
  in

  let tbox_init_size = textbox##style##height in
  Html.document##onkeydown <-
    (Html.handler
       (fun e -> match e##keyCode with
         | 13 -> (* ENTER key *)
           let keyEv = match Js.Opt.to_option (Html.CoerceTo.keyboardEvent e) with
             | None   -> assert false
             | Some t -> t in
           (* Special handling of ctrl key *)
           if keyEv##ctrlKey = Js._true then
             textbox##value <- Js.string ((Js.to_string textbox##value) ^ "\n");
           if keyEv##ctrlKey = Js._true || keyEv##shiftKey = Js._true then
             let rows_height = textbox##scrollHeight / (textbox##rows + 1) in
             let h = string_of_int (rows_height * (textbox##rows + 1) + 20) ^ "px" in
             textbox##style##height <- Js.string h;
             Js._true
           else begin
             execute ();
             textbox##style##height <- tbox_init_size;
             Js._false
           end
	 | 38 -> (* UP ARROW key *) begin
	   match !history_bckwrd with
	     | s :: l ->
	       let str = Js.to_string textbox##value in
	       history_frwrd := Js.string str :: !history_frwrd;
	       textbox##value <- s;
	       history_bckwrd := l;
	       Js._false
	     | _ -> Js._true
	 end
	 | 40 -> (* DOWN ARROW key *) begin
	   match !history_frwrd with
	     | s :: l ->
	       let str = Js.to_string textbox##value in
	       history_bckwrd := Js.string str :: !history_bckwrd;
	       textbox##value <- s;
	       history_frwrd := l;
	       Js._false
	     | _ -> Js._true
	 end
	 | _ -> Js._true));
  Tutorial.clear_fun := (fun _ ->
    output_area##innerHTML <- (Js.string "");
    textbox##focus();
    textbox##select()
  );
  Tutorial.reset_fun := (fun _ ->
    output_area##innerHTML <- (Js.string "");
    Toploop.initialize_toplevel_env ();
    Toploop.input_name := "";
    exec ppf "open Tutorial";
    textbox##focus();
    textbox##select()
  );
  Tutorial.set_cols_fun := (fun i ->
    textbox##style##width <- Js.string ((string_of_int (i * 7)) ^ "px"));

  let send_button = button "Send" (fun () -> execute ()) in
  let clear_button = button "Clear" (fun () -> Tutorial.clear ()) in
  let reset_button = button "Reset" (fun () -> Tutorial.reset ()) in
  let buttons =
      Js.Opt.get (doc##getElementById (Js.string "buttons"))
        (fun () -> assert false)
  in
  Tutorial.set_cols 80;
  Dom.appendChild buttons send_button;
  Dom.appendChild buttons clear_button;
  Dom.appendChild buttons reset_button;
  output_area##scrollTop <- output_area##scrollHeight;
  make_code_clickable ();
  (* Dom.appendChild output_area doc; *)
  start ppf;
  Js._false

let _ = Html.window##onload <- Html.handler run
