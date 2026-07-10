open Syntax

type state = {
  heap : int32 array;
  registers : int32 array;
  mutable free_regions : (int * int) list;
  allocations : (int, int) Hashtbl.t;
  emit : string -> unit;
}

let runtime message = Error.fail Error.Runtime message

let register st r = st.registers.(r)
let set_register st r value = st.registers.(r) <- value

let eval_value st = function Reg r -> register st r | Imm n -> n

let index_of_int32 who value =
  let index = Int32.to_int value in
  if index < 0 then runtime (who ^ ": invalid address");
  index

let shift_distance n = Int32.to_int (Int32.logand n 31l)

let eval_op2 op left right =
  match op with
  | Add -> Int32.add left right
  | Sub -> Int32.sub left right
  | Mul -> Int32.mul left right
  | Div ->
      if right = 0l then runtime "division by zero";
      Int64.to_int32
        (Int64.div (Int64.of_int32 left) (Int64.of_int32 right))
  | Mod ->
      if right = 0l then runtime "remainder by zero";
      Int64.to_int32
        (Int64.rem (Int64.of_int32 left) (Int64.of_int32 right))
  | Bit_and -> Int32.logand left right
  | Bit_or -> Int32.logor left right
  | Bit_xor -> Int32.logxor left right
  | Shl -> Int32.shift_left left (shift_distance right)
  | Shr -> Int32.shift_right left (shift_distance right)
  | Ushr -> Int32.shift_right_logical left (shift_distance right)
  | Lt -> if Int32.compare left right < 0 then 1l else 0l
  | Eq -> if left = right then 1l else 0l

let eval_op1 Bit_not value = Int32.lognot value

let rec allocate size regions =
  match regions with
  | [] -> None
  | (base, available) :: rest ->
      if size = available then Some (base, rest)
      else if size < available then
        Some (base, (base + size, available - size) :: rest)
      else
        match allocate size rest with
        | None -> None
        | Some (ptr, rest') -> Some (ptr, (base, available) :: rest')

let merge_regions regions =
  let sorted = List.sort (fun (a, _) (b, _) -> compare a b) regions in
  let rec loop acc = function
    | [] -> List.rev acc
    | (base, size) :: rest ->
        (match acc with
         | (prev_base, prev_size) :: tail
           when prev_base + prev_size = base ->
             loop ((prev_base, prev_size + size) :: tail) rest
         | _ -> loop ((base, size) :: acc) rest)
  in
  loop [] sorted

let malloc st size_value =
  let size = Int32.to_int size_value in
  if size_value < 0l then runtime "malloc OOM";
  if size = 0 then 0
  else
    match allocate size st.free_regions with
    | None -> runtime "malloc OOM"
    | Some (ptr, regions) ->
        st.free_regions <- regions;
        Hashtbl.replace st.allocations ptr size;
        ptr

let free st ptr =
  match Hashtbl.find_opt st.allocations ptr with
  | None -> runtime "free bad ptr"
  | Some size ->
      Hashtbl.remove st.allocations ptr;
      st.free_regions <- merge_regions ((ptr, size) :: st.free_regions)

let print_string st value =
  let word_index = ref (index_of_int32 "print_str" value) in
  let bytes = Buffer.create 32 in
  let finished = ref false in
  while not !finished do
    if !word_index >= Array.length st.heap then
      runtime "print_str invalid address";
    let word = st.heap.(!word_index) in
    List.iter
      (fun shift ->
        if not !finished then begin
          let byte =
            Int32.to_int
              (Int32.logand (Int32.shift_right_logical word shift) 255l)
          in
          if byte = 0 then finished := true
          else if byte > 127 then runtime "print_str encountered non-ASCII data"
          else Buffer.add_char bytes (Char.chr byte)
        end)
      [24; 16; 8; 0];
    incr word_index
  done;
  st.emit (Buffer.contents bytes)

let print_printable st = function
  | Id text -> st.emit text
  | Value value -> st.emit (Int32.to_string (eval_value st value))
  | Array (base_value, length_value) ->
      let base = Int32.to_int (eval_value st base_value) in
      let length = Int32.to_int (eval_value st length_value) in
      if base < 0 || length < 0 || base > Array.length st.heap - length then
        st.emit (Printf.sprintf "attempted to print invalid address %d" (base + length))
      else begin
        let out = Buffer.create 32 in
        Buffer.add_char out '[';
        for i = 0 to length - 1 do
          Buffer.add_string out (string_of_int (base + i));
          Buffer.add_string out "; "
        done;
        Buffer.add_char out ']';
        st.emit (Buffer.contents out)
      end

let eval_action st = function
  | Copy (r, value) -> set_register st r (eval_value st value)
  | Op1 (r, op, value) ->
      set_register st r (eval_op1 op (eval_value st value))
  | Op2 (r, op, left, right) ->
      let left = eval_value st left in
      let right = eval_value st right in
      set_register st r (eval_op2 op left right)
  | Load (r, address) ->
      let ptr = index_of_int32 "load" (eval_value st address) in
      if ptr >= Array.length st.heap then runtime "load invalid address";
      set_register st r st.heap.(ptr)
  | Store (r, value) ->
      let ptr = index_of_int32 "store" (register st r) in
      if ptr >= Array.length st.heap then runtime "store invalid address";
      st.heap.(ptr) <- eval_value st value
  | Malloc (r, size) ->
      set_register st r (Int32.of_int (malloc st (eval_value st size)))
  | Free r -> free st (index_of_int32 "free" (register st r))
  | Mem_size r -> set_register st r (Int32.of_int (Array.length st.heap))
  | Print printable -> print_printable st printable
  | Print_str value -> print_string st (eval_value st value)

let string_words text = (String.length text + 4) / 4

let pack_string heap start text =
  let byte_index = ref 0 in
  for word_index = 0 to string_words text - 1 do
    let word = ref 0l in
    List.iter
      (fun shift ->
        let byte =
          if !byte_index < String.length text then
            Char.code text.[!byte_index]
          else 0
        in
        word := Int32.logor !word (Int32.shift_left (Int32.of_int byte) shift);
        incr byte_index)
      [24; 16; 8; 0];
    heap.(start + word_index) <- !word
  done

let initialize_heap heap_size arguments =
  if List.exists
       (fun text -> not (String.for_all (fun ch -> Char.code ch <= 127) text))
       arguments
  then
    Error.fail Error.Usage "command-line argument is not ASCII";
  let count = List.length arguments in
  let string_words_total =
    List.fold_left (fun total text -> total + string_words text) 0 arguments
  in
  let heap_start = 2 + count + string_words_total in
  if heap_start > heap_size then runtime "not enough heap for command-line arguments";
  let heap = Array.make heap_size 0l in
  heap.(1) <- Int32.of_int count;
  let string_ptr = ref (2 + count) in
  List.iteri
    (fun index text ->
      heap.(2 + index) <- Int32.of_int !string_ptr;
      pack_string heap !string_ptr text;
      string_ptr := !string_ptr + string_words text)
    arguments;
  heap, heap_start

let run ~heap_size ~register_count ~blocks ~arguments ~emit =
  let heap, heap_start = initialize_heap heap_size arguments in
  let registers = Array.make register_count 0l in
  if register_count > 0 then registers.(0) <- Int32.of_int heap_start;
  let st = {
    heap;
    registers;
    free_regions =
      (if heap_start < heap_size then [heap_start, heap_size - heap_start] else []);
    allocations = Hashtbl.create 64;
    emit;
  } in
  let current = ref (Hashtbl.find blocks 0l) in
  let pc = ref 0 in
  let result = ref None in
  while !result = None do
    if !pc < Array.length (!current).actions then begin
      eval_action st (!current).actions.(!pc);
      incr pc
    end else
      match (!current).control with
      | Exit value -> result := Some (eval_value st value)
      | Abort -> runtime "called abort"
      | Goto value ->
          let target = eval_value st value in
          (match Hashtbl.find_opt blocks target with
           | None -> runtime ("goto(" ^ Int32.to_string target ^ ") invalid code address")
           | Some instr -> current := instr; pc := 0)
      | Ifz (value, zero_branch, nonzero_branch) ->
          current := if eval_value st value = 0l then zero_branch else nonzero_branch;
          pc := 0
  done;
  match !result with Some value -> value | None -> assert false
