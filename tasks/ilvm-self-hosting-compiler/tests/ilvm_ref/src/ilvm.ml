let parse text =
  let lexbuf = Lexing.from_string text in
  try Parser.program Lexer.token lexbuf with
  | Parsing.Parse_error ->
      let pos = lexbuf.Lexing.lex_curr_p in
      let column = pos.pos_cnum - pos.pos_bol + 1 in
      Error.fail Error.Parse
        (Printf.sprintf "parse error at line %d, column %d" pos.pos_lnum column)

let check blocks =
  let table = Hashtbl.create (List.length blocks) in
  List.iter
    (fun (number, instr) ->
      if Hashtbl.mem table number then Error.fail Error.Usage "duplicate block IDs";
      Hashtbl.add table number instr)
    blocks;
  if not (Hashtbl.mem table 0l) then Error.fail Error.Usage "Expected block 0";
  table

let run ?(heap_size = 16_777_216) ?(register_count = 64)
    ?(arguments = []) ?(emit = print_endline) text =
  let blocks = check (parse text) in
  Eval.run ~heap_size ~register_count ~blocks ~arguments ~emit
