type config = {
  heap_size : int;
  register_count : int;
  input : string;
  arguments : string list;
}

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let usage message = Error.fail Error.Usage message

let parse_positive name text =
  try
    let value = int_of_string text in
    if value < 0 then usage (name ^ " must be non-negative");
    value
  with Failure _ -> usage ("invalid " ^ name ^ ": " ^ text)

let parse argv =
  let heap_size = ref 16_777_216 in
  let register_count = ref 64 in
  let input = ref None in
  let arguments = ref [] in
  let argc = Array.length argv in
  let index = ref 1 in
  let next marker =
    if !index + 1 >= argc then usage ("expected value after " ^ marker);
    incr index;
    argv.(!index)
  in
  while !index < argc do
    let arg = argv.(!index) in
    (match !input, arg with
     | None, ("-m" | "--memory-limit") ->
         heap_size := parse_positive "memory limit" (next arg)
     | None, ("-r" | "--num-registers") ->
         register_count := parse_positive "register count" (next arg)
     | None, text when String.length text > 0 && text.[0] = '-' ->
         usage ("unknown option: " ^ text)
     | None, path -> input := Some path
     | Some _, "-l" -> arguments := next arg :: !arguments
     | Some _, "-f" -> arguments := read_file (next arg) :: !arguments
     | Some _, marker -> usage ("expected -l or -f in ILVM arguments, found " ^ marker));
    incr index
  done;
  let input = match !input with Some path -> path | None -> usage "missing input file" in
  { heap_size = !heap_size;
    register_count = !register_count;
    input;
    arguments = List.rev !arguments }
