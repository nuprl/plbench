type reg = int

type value = Reg of reg | Imm of int32

type op2 =
  | Add | Sub | Mul | Div | Mod
  | Bit_and | Bit_or | Bit_xor | Shl | Shr | Ushr | Lt | Eq

type op1 = Bit_not

type printable = Id of string | Value of value | Array of value * value

type action =
  | Op1 of reg * op1 * value
  | Op2 of reg * op2 * value * value
  | Copy of reg * value
  | Load of reg * value
  | Store of reg * value
  | Malloc of reg * value
  | Print of printable
  | Print_str of value
  | Free of reg
  | Mem_size of reg

type instr = { actions : action array; control : control }

and control =
  | Goto of value
  | Exit of value
  | Abort
  | Ifz of value * instr * instr

type block = int32 * instr
