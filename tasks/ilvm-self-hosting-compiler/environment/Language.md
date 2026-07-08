# The ILVM Language

ILVM (*intermediate-level virtual machine*) is a small, register-based
assembly-like language. It provides a few higher-level features:

- a `malloc`/`free` heap allocator, with allocator metadata kept outside of
  program-addressable memory (a program cannot corrupt it),
- a structured `ifz ... else ...` conditional (in addition to unconditional
  jumps),
- instructions for printing to the screen.

ILVM has a Harvard architecture: code and data live in separate address
spaces. There is no call stack, no functions, and no notion of a heap object
having a type — the heap is just an array of 32-bit words.

This document specifies the syntax and semantics of the language itself.

## 1. Lexical structure

An ILVM source file is a sequence of the following tokens, separated by
whitespace and comments (both of which are otherwise insignificant):

| Token class      | Form                                              |
|-------------------|---------------------------------------------------|
| Register          | `r` followed immediately by one or more digits, e.g. `r0`, `r17` |
| Integer literal    | an optional `-` or `+` sign and one or more digits, e.g. `42`, `-7`, `+3` |
| Identifier string  | one or more alphanumeric characters enclosed in double quotes, e.g. `"hello123"` |
| Keywords           | `block` `goto` `exit` `abort` `ifz` `else` `malloc` `memsize` `free` `print` `print_str` `array` |
| Punctuation        | `{` `}` `(` `)` `,` `;` `=` |
| Operators          | `+` `-` `*` `/` `%` `&` `\|` `^` `<<` `>>` `>>>` `==` `<` `~` |

**Comments.** `//` begins a line comment that runs to the end of the line.
There are no block comments.

**Whitespace.** Space, tab, and newline characters separate tokens and are
otherwise ignored.

An integer literal denotes a signed 32-bit value and must lie in the range
−2147483648 to 2147483647; a literal outside that range is a parse error.

## 2. Context-free grammar

Terminals are shown in double quotes. `reg`, `int`, and `ident` are the
lexical classes from §1.

```
Program        ::= Block+

Block          ::= "block" int "{" Instr "}"

Val            ::= reg
                  | int

Op2            ::= "+" | "-" | "*" | "/" | "%"
                  | "&" | "|" | "^" | "<<" | ">>" | ">>>"
                  | "==" | "<"

Op1            ::= "~"

Printable      ::= ident
                  | Val
                  | "array" "(" Val "," Val ")"

Instr          ::= "goto" "(" Val ")" ";"
                  | "exit" "(" Val ")" ";"
                  | "abort" ";"
                  | reg "=" "*" Val ";" Instr
                  | "*" reg "=" Val ";" Instr
                  | reg "=" "malloc" "(" Val ")" ";" Instr
                  | reg "=" "memsize" ";" Instr
                  | reg "=" Op1 Val ";" Instr
                  | reg "=" Val Op2 Val ";" Instr
                  | reg "=" Val ";" Instr
                  | "ifz" Val "{" Instr "}" "else" "{" Instr "}"
                  | "free" "(" reg ")" ";" Instr
                  | "print" "(" Printable ")" ";" Instr
                  | "print_str" "(" Val ")" ";" Instr
```

An `ifz` arm is a nested instruction sequence, not a `Block`: it has no
block number, so it cannot be the target of a `goto`.

## 3. Static well-formedness

A parsed program is checked for the following conditions before it runs; a
program that fails one of these is rejected as a whole and never executed:

1. **Unique block numbers.** No two `Block`s may declare the same number.
2. **Block 0 exists.** Execution always begins at the block numbered `0`;
   a program with no `block 0 { ... }` is rejected.

Blocks may be listed in any order.

## 4. Machine state

The machine's state consists of:

- **Registers**: an array `r0 .. r(k-1)` of 32-bit signed integers, where
  `k` is the register count (§7). All registers are initialized to `0`,
  except `r0` (§8).
- **Heap**: an array of `m` 32-bit signed words, addressed `0 .. m-1`, where
  `m` is the memory limit (§7). All heap words are initialized to `0`,
  except for a region at the low end of the heap that is pre-populated with
  initial argument data (§8).
- **Allocator state**: bookkeeping used by `malloc`/`free` (§6.4). This
  state is *not* part of the addressable heap: no program instruction can
  read or corrupt it.
- **Program counter**: which instruction executes next. It is not an
  addressable register.

The **word size is 32 bits** throughout: every register, every heap cell,
and every immediate is a 32-bit signed two's-complement integer. Arithmetic
that overflows 32 bits wraps around (two's-complement wraparound); a program
may rely on this.

A `Val` evaluates to a 32-bit integer: an immediate evaluates to itself, a
register to its current contents.

## 5. Control flow

Execution begins at block `0`. There is no fall-through between blocks (§2);
control moves only by:

- `goto(v);` — jump to the block whose number equals the value of `v`. If
  no block has that number, this is a runtime error (§6.5).
- `exit(v);` — halt the program successfully; `v` is the program's result.
  `ilvm` reports this by printing `Normal termination. Result = v` to the
  screen. This is separate from `ilvm`'s own exit status as a command:
  `ilvm` exits with status `0` for any successful `exit(v)` regardless of
  `v`, and status `1` if the program instead hits a runtime error or
  `abort`.
- `abort;` — halt the program with a runtime error.

`ifz v { S1 } else { S2 }` executes `S1` if `v` is zero, and `S2`
otherwise:

```
block 0 {
    r1 = 5;
    ifz r1 {
        goto(1);
    } else {
        goto(2);
    }
}
block 1 { exit(0); }   // r1 == 0
block 2 { exit(1); }   // r1 != 0
```

**Example — factorial of 5, using a loop implemented with blocks:**

```
block 0 {
    r2 = 1;    // accumulator
    r1 = 5;    // counter
    goto(1);
}
block 1 {
    ifz r1 {
        exit(r2);              // done: r2 holds 5!
    }
    else {
        r2 = r2 * r1;
        r1 = r1 - 1;
        goto(1);                // loop
    }
}
```

This terminates with result `120`.

**Example — indirect (computed) jump:**

```
block 0 {
    r0 = 10;
    r1 = r0 - 9;   // r1 = 1
    goto(r1);      // jumps to block 1
}
block 1 {
    exit(0);
}
```

## 6. Instructions

### 6.1 Data movement and arithmetic

- **`r = v;`** — set `r` to the value of `v`.
- **`r = op1 v;`** — apply unary operator `op1` to `v`, storing the result
  in `r`. The only unary operator is `~`, bitwise NOT.
- **`r = v1 op2 v2;`** — apply binary operator `op2` to `v1` and `v2` (in
  that order), storing the result in `r`.

Operands are read before `r` is assigned, so an instruction like
`r = r + 1;` reads the old value of `r`.

The binary operators:

| Operator | Meaning |
|----------|---------|
| `+`      | addition (wraps on overflow) |
| `-`      | subtraction (wraps on overflow) |
| `*`      | multiplication (wraps on overflow) |
| `/`      | signed integer division, truncating toward zero |
| `%`      | signed integer remainder (sign follows the dividend, matching `/`) |
| `&`      | bitwise AND |
| `\|`      | bitwise OR |
| `^`      | bitwise XOR |
| `<<`     | logical left shift |
| `>>`     | **arithmetic** (sign-extending) right shift |
| `>>>`    | **logical** (zero-filling) right shift, i.e. the left operand is treated as unsigned for the purpose of the shift |
| `==`     | equality: `1` if equal, else `0` |
| `<`      | signed less-than: `1` if the left operand is less than the right, else `0` |

For the shifts `<<`, `>>`, and `>>>`, only the low 5 bits of the right
operand are used as the shift distance (i.e. the distance is taken modulo
32). For example:

```
block 0 {
    r0 = 1;
    r1 = 1 << 32;   // r1 = 1   (32 mod 32 == 0)
    r2 = 1 << 33;   // r2 = 2   (33 mod 32 == 1)
    r3 = 1 << -1;   // r3 = -2147483648   (-1 mod 32 == 31)
    exit(0);
}
```

Another example, showing the bitwise and shift operators:

```
block 0 {
    r0 = 12 & 10;       // r0 = 8
    r1 = 12 | 10;       // r1 = 14
    r2 = r0 ^ r1;       // r2 = 6
    r3 = ~ r2;          // r3 = -7
    r4 = -8 >> 1;       // r4 = -4   (arithmetic shift keeps the sign)
    r5 = -8 >>> 1;      // r5 = 2147483644  (logical shift fills with 0)
    r6 = 3 << 4;        // r6 = 48
    exit(0);
}
```

`/` and `%` by a divisor of `0` are a fatal error; see §6.5.

### 6.2 Heap access

- **`r = *v;`** (load) — set `r` to the heap word at address `v`.
- **`*r = v;`** (store) — set the heap word at address `r` to the value
  `v`.

An address is interpreted as unsigned: a negative value denotes a large
non-negative address, which is normally out of bounds (§6.5).

```
block 0 {
    r0 = 10;
    r1 = r0 * 2;   // r1 = 20
    *r1 = 50;      // heap[20] = 50
    r2 = *r1;      // r2 = heap[20] = 50
    exit(0);
}
```

### 6.3 Printing

- **`print(v);`** — print the value of `v` as a decimal integer, followed
  by a newline.
- **`print("ident");`** — print the text `ident`, followed by a newline.
- **`print(array(v1, v2));`** — print the addresses
  `v1, v1+1, ..., v1+v2-1` as a bracketed, semicolon-separated list
  followed by a newline, e.g. `[10; 11; 12; ]`. Despite the name, it prints
  the addresses themselves, **not** the values stored at them. If any
  address in the range is out of bounds, it prints a diagnostic message
  instead.
- **`print_str(v);`** — print, as text followed by a newline, the
  NUL-terminated ASCII string stored in the heap starting at address `v`
  (see §8 for the string encoding). It is a runtime error if the string
  runs past the end of the heap without a NUL terminator, or if it contains
  non-ASCII bytes.

```
block 0 {
    print("hello123");   // prints: hello123
    r0 = 42;
    print(r0);            // prints: 42
    print(99);            // prints: 99
    print(array(r0, 3));  // prints: [42; 43; 44; ]
    exit(0);
}
```

### 6.4 Memory allocation

- **`r = malloc(v);`** — allocate a block of `v` **words** (not bytes) and
  set `r` to its base address. If `v` is `0`, no block is allocated and `r`
  is set to `0`. If there is no free region large enough to satisfy the
  request, this is a runtime error (out-of-memory, §6.5).
- **`free(r);`** — free the block previously allocated at the address in
  `r`.
- **`r = memsize;`** — set `r` to the total size of the heap, in words (the
  configured memory limit, §7).

The allocator's bookkeeping is stored entirely outside the addressable
heap: a program cannot corrupt it by writing to heap addresses, and
`malloc`/`free` cannot be affected by heap contents.

```
block 0 {
    r0 = malloc(10);   // r0 = base address of a 10-word block
    exit(r0);
}
```

### 6.5 Runtime errors

The following conditions halt the program abnormally (they are *not*
catchable from within an ILVM program):

- `goto(v)` where `v` is not the number of any block.
- `r = *v` or `*r = v` where the address is `>=` the heap size.
- `print_str(v)` where the string has no NUL terminator before the end of
  the heap, or contains a non-ASCII byte.
- `malloc(v)` where no free region of `v` or more words exists.
- `free(r)` where the value in `r` is not the base address of a currently
  live allocation (e.g. it was never returned by `malloc`, or has already
  been freed).
- `abort;`, unconditionally.
- Division or remainder (`/`, `%`) by `0`.

Using a register index `>=` the register count (§7) is **undefined
behavior**.

## 7. Configuration

Two parameters are fixed by flags to `ilvm` when a program is run, not by
the program's own source text:

- **Memory limit** (`-m` / `--memory-limit`, default `16777216`): the
  number of words `m` in the heap. Available to a running program via
  `memsize` (§6.4).
- **Register count** (`-r` / `--num-registers`, default `64`): the number
  of registers `k`. Valid register names in a running program are `r0`
  through `r(k-1)`.

## 8. Command-line arguments and strings

An ILVM program can receive a sequence of string arguments on the command
line, passed to `ilvm` as a sequence of `-l literal` and/or
`-f path/to/file` markers after the program's source file, in any
combination and order — the two marker kinds need not literally alternate:

```
./ilvm program.ilvm -l a -l b -f file.txt -l c
```

Each marker introduces one argument: `-l value` passes `value` itself, and
`-f path` passes the literal contents of the file at `path`.

Each argument must consist entirely of ASCII bytes (`0x00`-`0x7f`); a
non-ASCII byte is rejected before the program starts. A NUL byte (`0x00`)
is ASCII and so is accepted, but once packed into the heap it terminates
the argument's string for `print_str` (§6.3).

Before execution, the arguments are laid out at the low end of the heap; if
the memory limit (§7) is too small to hold them, the program is rejected
before it starts. The layout:

- **Heap address `0`** is left as `0` and never used by the argument
  layout.
- **Heap address `1`** holds `N`, the number of arguments.
- **Heap addresses `2` through `N+1`** hold `N` pointers: the heap address
  at which each argument's packed string data begins, in order.
- Immediately after that pointer table, the packed string data for each
  argument follows in order (see the packing format below).
- **Register `r0`** is initialized to the first heap address *after* all of
  that data. This is also the first address `malloc` may return.

**String packing.** Strings are stored as NUL-terminated ASCII, four bytes
packed per 32-bit heap word, in network (big-endian) byte order — i.e. the
first character of the string is the most-significant byte of the first
word. For example, the string `"ABC"` (3 characters plus a NUL terminator
fits in one word) is stored as the single word `0x41424300` (`'A' 'B' 'C'
\0`). A longer string spans multiple consecutive words; the NUL terminator
byte can fall anywhere within a word (it is not required to be
word-aligned), and any bytes in the final word after the NUL are unspecified
padding.

`print_str(v)` (§6.3) reads this format, most-significant byte of each word
first, stopping at the first NUL byte.

**Example.** With one command-line argument `"hi"`:

- `heap[1] = 1` (one argument)
- `heap[2] = 3` — the argument's string data starts at address 3. The
  pointer table occupies just `heap[2]` (one word, since `N = 1`), so the
  string-data region starts right after it, at address `2 + N = 3`.
- `heap[3]` holds `"hi"` packed as one word: `0x68690000` (`'h' 'i' \0` and
  one padding byte)
- `r0` is initialized to `4`, the first free address after that one word of
  string data.

```
block 0 {
    r1 = *2;          // r1 = address of argument 0's string data
    print_str(r1);    // prints: hi
    exit(0);
}
```

**Zero-argument case.** With no arguments (`N = 0`), the pointer table and
string-data region are both empty, so `r0 = 2`, right after the count word
at address `1`.
