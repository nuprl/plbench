(** MiniScheme CLI: mscheme [-l FILE]... [-e EXPR] [FILE] *)

open Value

let usage () =
  prerr_endline "usage: mscheme [-l FILE]... [-e EXPR] [FILE]";
  exit 2

let () =
  let loads = ref [] in
  let expr = ref None in
  let files = ref [] in
  let args = Array.to_list Sys.argv |> List.tl in
  let rec parse = function
    | [] -> ()
    | "-h" :: _ | "--help" :: _ ->
        print_endline "usage: mscheme [-l FILE]... [-e EXPR] [FILE]";
        exit 0
    | "-e" :: e :: rest ->
        expr := Some e;
        parse rest
    | "-e" :: [] -> usage ()
    | "-l" :: f :: rest ->
        loads := !loads @ [ f ];
        parse rest
    | "-l" :: [] -> usage ()
    | f :: rest ->
        files := !files @ [ f ];
        parse rest
  in
  parse args;
  let env = Eval.make_global_env () in
  try
    List.iter (fun p -> ignore (Eval.load_file p env)) !loads;
    let result = ref None in
    List.iter
      (fun p -> result := Some (Eval.load_file p env))
      !files;
    (match !expr with
    | Some e -> result := Some (Eval.eval_toplevel (Reader.read_all e) env)
    | None -> ());
    if !files <> [] || !expr <> None then (
      (match !result with
      | Some v -> print_endline (to_string v)
      | None -> ());
      exit 0);
    (* REPL *)
    print_endline "MiniScheme (host). Ctrl-D to exit.";
    let buf = Buffer.create 256 in
    let rec repl () =
      try
        print_string (if Buffer.length buf = 0 then "> " else "... ");
        flush stdout;
        let line = input_line stdin in
        Buffer.add_string buf line;
        Buffer.add_char buf '\n';
        try
          let forms = Reader.read_all (Buffer.contents buf) in
          Buffer.clear buf;
          let v = Eval.eval_toplevel forms env in
          print_endline (to_string v);
          repl ()
        with Parse_error _ -> repl ()
      with End_of_file ->
        print_newline ();
        exit 0
    in
    try repl () with
    | Type_error msg ->
        prerr_endline ("error: " ^ msg);
        exit 1
    | Runtime_error msg ->
        prerr_endline ("error: " ^ msg);
        exit 1
  with
  | Type_error msg ->
      prerr_endline ("error: " ^ msg);
      exit 1
  | Runtime_error msg ->
      prerr_endline ("error: " ^ msg);
      exit 1
  | Parse_error msg ->
      prerr_endline ("error: " ^ msg);
      exit 1
  | Sys_error msg ->
      prerr_endline ("error: " ^ msg);
      exit 1
