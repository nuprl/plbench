open Cmdliner

let parse_file path =
  try Ok (Parser.parse_file path)
  with Sys_error message | Parser.Error message -> Error message


let exec path =
  match parse_file path with
  | Error message -> `Error (false, "parse error: " ^ message)
  | Ok expression -> (
      try
        let outcome = Semantics.run expression in
        let output =
          match outcome with
          | Semantics.Integer value -> string_of_int value
          | Semantics.Boolean value -> string_of_bool value
          | Semantics.Function -> "<function>"
        in
        print_endline output;
        `Ok ()
      with
      | Semantics.Static_error message -> `Error (false, "static error: " ^ message)
      | Semantics.Runtime_error message ->
          `Error (false, "runtime error: " ^ message))

let type_check path =
  match parse_file path with
  | Error message -> `Error (false, "parse error: " ^ message)
  | Ok expression -> (
      try
        ignore (Semantics.infer expression);
        `Ok ()
      with Semantics.Static_error message ->
        `Error (false, "static error: " ^ message))


let is_migration original_path migrated_path =
  match (parse_file original_path, parse_file migrated_path) with
  | Error message, _ | _, Error message -> `Error (false, message)
  | Ok original, Ok migrated -> (
      try
        print_endline (string_of_bool (Migration.check ~original ~migrated));
        `Ok ()
      with Semantics.Static_error message -> `Error (false, message))

let precision_distance less_path more_path =
  match (parse_file less_path, parse_file more_path) with
  | Error message, _ | _, Error message -> `Error (false, message)
  | Ok less_precise, Ok more_precise -> (
      try
        match Migration.distance ~less_precise ~more_precise with
        | Some distance ->
            Printf.printf "%d\n%!" distance;
            `Ok ()
        | None -> `Error (false, "programs are not pointwise comparable")
      with Semantics.Static_error message -> `Error (false, message))


let count_anys path =
  match parse_file path with
  | Error message -> `Error (false, message)
  | Ok expression -> (
      try
        ignore (Semantics.infer expression);
        Printf.printf "%d\n%!" (Syntax.count_anys expression);
        `Ok ()
      with Semantics.Static_error message -> `Error (false, message))


let file_argument ~position ~docv doc =
  Arg.(required & pos position (some file) None & info [] ~docv ~doc)


let exec_command =
  let doc = "evaluate a closed GTLC program" in
  let man =
    [ `S Manpage.s_description;
      `P
        "Parses, elaborates, and evaluates FILE according to Language.md. The result \
         is printed as a decimal integer, true, false, or <function>. A failing \
         guarded cast is reported as an error. Evaluation has no fuel limit, so a \
         diverging GTLC program does not terminate."
    ]
  in
  let file = file_argument ~position:0 ~docv:"FILE" "GTLC program to evaluate." in
  Cmd.v (Cmd.info "exec" ~doc ~man) Term.(ret (const exec $ file))

let type_check_command =
  let doc = "check that a GTLC program is well typed" in
  let man =
    [ `S Manpage.s_description;
      `P
        "Parses and type-checks FILE. Produces no output on success. A parse or \
         static type error is reported as a command error."
    ]
  in
  let file = file_argument ~position:0 ~docv:"FILE" "GTLC program to check." in
  Cmd.v (Cmd.info "type-check" ~doc ~man) Term.(ret (const type_check $ file))


let is_migration_command =
  let doc = "check the syntactic migration relation between two GTLC programs" in
  let man =
    [ `S Manpage.s_description;
      `P
        "First type-checks both programs. A static error is reported as a command \
         error, not as false. For two well-typed programs, prints true exactly when \
         they have identical non-type syntax, including variable and binder names, and \
         the complete expression structure is identical, including the presence of \
         every ascription, and every type in MIGRATED is at least as precise as its \
         corresponding type in ORIGINAL. A missing lambda annotation denotes any.";
      `P "The result is determined by the programs' syntax and type decorations."
    ]
  in
  let original =
    file_argument ~position:0 ~docv:"ORIGINAL"
      "Original, normally unannotated, GTLC program."
  in
  let migrated =
    file_argument ~position:1 ~docv:"MIGRATED" "Proposed migrated GTLC program."
  in
  Cmd.v
    (Cmd.info "is-migration" ~doc ~man)
    Term.(ret (const is_migration $ original $ migrated))

let precision_distance_command =
  let doc = "count pointwise precision-refinement steps" in
  let man =
    [ `S Manpage.s_description;
      `P
        "First type-checks both programs, then prints the number of single-edge \
         precision refinements from LESS to MORE. The command fails when the \
         programs differ structurally or corresponding types are incomparable."
    ]
  in
  let less =
    file_argument ~position:0 ~docv:"LESS" "Less-precise GTLC program."
  in
  let more =
    file_argument ~position:1 ~docv:"MORE" "More-precise GTLC program."
  in
  Cmd.v
    (Cmd.info "precision-distance" ~doc ~man)
    Term.(ret (const precision_distance $ less $ more))


let count_anys_command =
  let doc = "count explicit any occurrences in a GTLC program" in
  let man =
    [ `S Manpage.s_description;
      `P
        "Type-checks FILE, then prints the number of lambda annotations and expression \
         ascriptions whose complete type is any. A missing lambda annotation counts \
         as an implicit any."
    ]
  in
  let file = file_argument ~position:0 ~docv:"FILE" "GTLC program to inspect." in
  Cmd.v (Cmd.info "count-anys" ~doc ~man) Term.(ret (const count_anys $ file))


let command =
  let doc = "reference tools for the gradual lambda calculus" in
  let man =
    [ `S Manpage.s_description;
      `P
        "GTLC is the executable reference implementation accompanying Language.md. It \
         evaluates programs and recognizes the task's syntactic migration relation."
    ]
  in
  Cmd.group
    (Cmd.info "gtlc" ~version:"1.0" ~doc ~man)
    [ exec_command;
      type_check_command;
      is_migration_command;
      precision_distance_command;
      count_anys_command
    ]


let () = exit (Cmd.eval command)
