(** S-expression reader for MiniScheme. *)

open Value

let is_delim = function
  | ' ' | '\t' | '\n' | '\r' | '(' | ')' | '"' | ';' | '\'' -> true
  | _ -> false

let tokenize (src : string) : string list =
  let n = String.length src in
  let tokens = ref [] in
  let i = ref 0 in
  let push t = tokens := t :: !tokens in
  while !i < n do
    let c = src.[!i] in
    if c = ' ' || c = '\t' || c = '\n' || c = '\r' then incr i
    else if c = ';' then (
      while !i < n && src.[!i] <> '\n' do
        incr i
      done)
    else if c = '(' || c = ')' then (
      push (String.make 1 c);
      incr i)
    else if c = '\'' then (
      push "'";
      incr i)
    else if c = '"' then (
      let buf = Buffer.create 16 in
      Buffer.add_char buf '"';
      incr i;
      let closed = ref false in
      while !i < n && not !closed do
        match src.[!i] with
        | '\\' ->
            if !i + 1 >= n then raise (Parse_error "unterminated string escape");
            (match src.[!i + 1] with
            | 'n' -> Buffer.add_char buf '\n'
            | 't' -> Buffer.add_char buf '\t'
            | '"' -> Buffer.add_char buf '"'
            | '\\' -> Buffer.add_char buf '\\'
            | e ->
                raise
                  (Parse_error (Printf.sprintf "bad escape \\%c" e)));
            i := !i + 2
        | '"' ->
            Buffer.add_char buf '"';
            incr i;
            closed := true
        | ch ->
            Buffer.add_char buf ch;
            incr i
      done;
      if not !closed then raise (Parse_error "unterminated string");
      push (Buffer.contents buf))
    else
      let j = ref !i in
      while !j < n && not (is_delim src.[!j]) do
        incr j
      done;
      push (String.sub src !i (!j - !i));
      i := !j
  done;
  List.rev !tokens

let atom (tok : string) : t =
  if tok = "#t" then Bool true
  else if tok = "#f" then Bool false
  else if
    String.length tok >= 2
    && tok.[0] = '"'
    && tok.[String.length tok - 1] = '"'
  then String (String.sub tok 1 (String.length tok - 2))
  else
    try
      if String.contains tok '.' then Float (float_of_string tok)
      else Int (int_of_string tok)
    with Failure _ -> Symbol tok

type reader = { tokens : string array; mutable i : int }

let peek r =
  if r.i >= Array.length r.tokens then None else Some r.tokens.(r.i)

let next r =
  match peek r with
  | None -> raise (Parse_error "unexpected end of input")
  | Some t ->
      r.i <- r.i + 1;
      t

let rec read_one r : t =
  let t = next r in
  if t = "(" then (
    let items = ref [] in
    let rec loop () =
      match peek r with
      | None -> raise (Parse_error "unterminated list")
      | Some ")" ->
          ignore (next r);
          List (List.rev !items)
      | Some _ ->
          items := read_one r :: !items;
          loop ()
    in
    loop ())
  else if t = ")" then raise (Parse_error "unexpected ')'")
  else if t = "'" then List [ Symbol "quote"; read_one r ]
  else atom t

let read_all (src : string) : t list =
  let r = { tokens = Array.of_list (tokenize src); i = 0 } in
  let forms = ref [] in
  while peek r <> None do
    forms := read_one r :: !forms
  done;
  List.rev !forms
