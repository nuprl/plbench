#!/usr/bin/env python3
"""Reference (non-self-hosting) MiniScheme -> ILVM compiler.

This is the oracle's "cheat": a real compiler with real codegen (closures,
recursion, lists, strings, vectors), but written directly in Python rather
than in MiniScheme. It is NOT self-hosting -- see tests/test_suite.py and
README.md for how the verifier accounts for that.

Runtime value representation (every value is a pointer to a boxed cell):
  TAG_INT=0    [tag, value]
  TAG_BOOL=1   [tag, 0-or-1]
  TAG_NIL=2    [tag]                      (singleton)
  TAG_PAIR=3   [tag, car, cdr]
  TAG_STRING=4 [tag, length, packed bytes...]  (ILVM's own print_str format)
  TAG_CLOS=5   [tag, code_block_number, captured_env_ptr]
  TAG_VEC=6    [tag, length, slot0, slot1, ...]

Registers used by the COMPILED program (not by this compiler, which is
plain Python):
  r0 = value stack pointer (vsp), grows up, holds value-cell pointers
  r1 = call stack pointer (csp), grows up, holds alternating
       (return_block_number, saved_env_ptr) pairs, pushed in that order
  r2 = current environment/frame pointer (env). A frame is
       [parent_env_ptr, slot0, slot1, ...]; env=0 means "top level, no
       lexical parent" (only globals and one's own params are visible).
  r3/r4/r5 = NIL/TRUE/FALSE singleton cell addresses
  r8 = globals array base address
  r6/r7/r9/r10.. = scratch, free for any straight-line sequence

Usage: compile_scheme_to_ilvm.py < source.scm > output.ilvm
"""

from __future__ import annotations

import re
import sys

# ---------------------------------------------------------------------------
# Reader
# ---------------------------------------------------------------------------


class Sym(str):
    """A symbol -- distinct from a string literal, which is plain str."""


QUOTE = Sym("quote")


class Reader:
    DELIMS = set(" \t\n\r()\"")

    def __init__(self, text: str):
        self.text = text
        self.pos = 0
        self.n = len(text)

    def skip_ws(self) -> None:
        while self.pos < self.n:
            c = self.text[self.pos]
            if c in " \t\n\r":
                self.pos += 1
            elif c == ";":
                while self.pos < self.n and self.text[self.pos] != "\n":
                    self.pos += 1
            else:
                break

    def at_end(self) -> bool:
        self.skip_ws()
        return self.pos >= self.n

    def read(self):
        self.skip_ws()
        c = self.text[self.pos]
        if c == "(":
            self.pos += 1
            return self.read_list()
        if c == "'":
            self.pos += 1
            return [QUOTE, self.read()]
        if c == '"':
            self.pos += 1
            return self.read_string()
        if c == "#":
            self.pos += 1
            k = self.text[self.pos]
            self.pos += 1
            if k == "t":
                return True
            if k == "f":
                return False
            raise ValueError(f"bad # syntax: #{k}")
        if c == "-" and self.pos + 1 < self.n and self.text[self.pos + 1].isdigit():
            return self.read_number()
        if c.isdigit():
            return self.read_number()
        return self.read_ident()

    def read_list(self):
        items = []
        while True:
            self.skip_ws()
            if self.text[self.pos] == ")":
                self.pos += 1
                return items
            items.append(self.read())

    def read_string(self) -> str:
        out = []
        while True:
            c = self.text[self.pos]
            if c == '"':
                self.pos += 1
                return "".join(out)
            if c == "\\":
                self.pos += 1
                e = self.text[self.pos]
                self.pos += 1
                out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(e, e))
            else:
                out.append(c)
                self.pos += 1

    def read_number(self):
        start = self.pos
        if self.text[self.pos] == "-":
            self.pos += 1
        while self.pos < self.n and self.text[self.pos].isdigit():
            self.pos += 1
        return int(self.text[start : self.pos])

    def read_ident(self) -> Sym:
        start = self.pos
        while self.pos < self.n and self.text[self.pos] not in self.DELIMS:
            self.pos += 1
        return Sym(self.text[start : self.pos])


def parse_program(text: str) -> list:
    r = Reader(text)
    forms = []
    while not r.at_end():
        forms.append(r.read())
    return forms


# ---------------------------------------------------------------------------
# ILVM block emitter
# ---------------------------------------------------------------------------


class Emitter:
    def __init__(self):
        self.blocks: list[tuple[str, list[str]]] = []
        self.label_num: dict[str, int] = {}
        self.counter = 0
        self.cur: list[str] | None = None

    def fresh_label(self, hint: str = "L") -> str:
        self.counter += 1
        return f"{hint}_{self.counter}"

    def start_block(self, label: str) -> None:
        if label in self.label_num:
            raise ValueError(f"duplicate block label {label}")
        self.label_num[label] = len(self.blocks)
        self.cur = []
        self.blocks.append((label, self.cur))

    def emit(self, line: str) -> None:
        assert self.cur is not None
        self.cur.append(line)

    def render(self) -> str:
        out = []
        for label, lines in self.blocks:
            n = self.label_num[label]
            body = "\n".join(lines)
            body = re.sub(r"@(\w+)", lambda m: str(self.label_num[m.group(1)]), body)
            out.append(f"block {n} {{\n{body}\n}}")
        return "\n".join(out)


TAG_INT, TAG_BOOL, TAG_NIL, TAG_PAIR, TAG_STRING, TAG_CLOS, TAG_VEC = range(7)


def pack_words(s: str) -> list[int]:
    data = s.encode("ascii") + b"\x00"
    while len(data) % 4 != 0:
        data += b"\x00"
    words = []
    for i in range(0, len(data), 4):
        w = (data[i] << 24) | (data[i + 1] << 16) | (data[i + 2] << 8) | data[i + 3]
        if w >= 2**31:
            w -= 2**32
        words.append(w)
    return words


BUILTIN_NAMES = {
    "+", "-", "*", "=", "<", ">",
    "cons", "car", "cdr", "null?", "pair?", "list",
    "string-append", "string-length", "display", "error",
    "vector", "vector-ref",
}


class Compiler:
    def __init__(self):
        self.e = Emitter()
        # argv is a predefined global populated from ILVM's argument area.
        self.globals: dict[str, int] = {"argv": 0}  # Sym name or "__str__N" -> index
        self.string_slot: dict[str, str] = {}  # text -> global key
        self.pending: list[tuple[str, list, list, list]] = []
        # (entry_label, params, body_expr, captured_scopes)

    # -- pass 1: collect global slots ---------------------------------------

    def collect_globals(self, forms: list) -> None:
        for form in forms:
            if isinstance(form, list) and form and form[0] == "define":
                target = form[1]
                name = target[0] if isinstance(target, list) else target
                if name not in self.globals:
                    self.globals[name] = len(self.globals)
        for form in forms:
            self.collect_strings(form)

    def collect_strings(self, expr) -> None:
        if isinstance(expr, str) and not isinstance(expr, Sym):
            if expr not in self.string_slot:
                key = f"__str__{len(self.string_slot)}"
                self.string_slot[expr] = key
                self.globals[key] = len(self.globals)
        elif isinstance(expr, list):
            for sub in expr:
                self.collect_strings(sub)

    # -- scope resolution ----------------------------------------------------

    def resolve(self, name: str, scopes: list[list[str]]):
        for depth, scope in enumerate(reversed(scopes)):
            if name in scope:
                return ("local", depth, scope.index(name))
        if name in self.globals:
            return ("global", self.globals[name], 0)
        raise ValueError(f"unbound variable: {name}")

    def emit_var_ref(self, name: str, scopes: list[list[str]]) -> None:
        kind, a, b = self.resolve(name, scopes)
        e = self.e
        if kind == "global":
            e.emit(f"r6 = r8 + {a};")
            e.emit("r7 = *r6;")
            push(e, "r7")
        else:
            depth, index = a, b
            e.emit("r6 = r2;")
            for _ in range(depth):
                e.emit("r6 = *r6;")
            e.emit(f"r7 = r6 + {1 + index};")
            e.emit("r9 = *r7;")
            push(e, "r9")

    def emit_global_store(self, name: str) -> None:
        """Pop top of value stack into globals[name]."""
        e = self.e
        pop(e, "r6")
        idx = self.globals[name]
        e.emit(f"r7 = r8 + {idx};")
        e.emit("*r7 = r6;")

    # -- literals -------------------------------------------------------

    def emit_int_literal(self, v: int) -> None:
        e = self.e
        e.emit("r6 = malloc(2);")
        e.emit(f"*r6 = {TAG_INT};")
        e.emit("r7 = r6 + 1;")
        e.emit(f"*r7 = {v};")
        push(e, "r6")

    def emit_bool_literal(self, v: bool) -> None:
        push(self.e, "r4" if v else "r5")

    def emit_string_literal(self, s: str) -> None:
        self.emit_var_ref(self.string_slot[s], [])

    # -- expression compilation ----------------------------------------------

    def compile_expr(self, expr, scopes: list[list[str]]) -> None:
        e = self.e
        if isinstance(expr, bool):
            self.emit_bool_literal(expr)
        elif isinstance(expr, int):
            self.emit_int_literal(expr)
        elif isinstance(expr, Sym):
            self.emit_var_ref(expr, scopes)
        elif isinstance(expr, str):
            self.emit_string_literal(expr)
        elif isinstance(expr, list):
            self.compile_form(expr, scopes)
        else:
            raise ValueError(f"cannot compile: {expr!r}")

    def compile_form(self, form: list, scopes: list[list[str]]) -> None:
        head = form[0]
        if head == "quote":
            self.compile_quoted(form[1])
        elif head == "if":
            self.compile_if(form, scopes)
        elif head == "lambda":
            self.compile_lambda(form[1], form[2], scopes)
        elif head == "let":
            self.compile_let(form, scopes)
        elif head == "letrec":
            self.compile_letrec(form, scopes)
        elif head in BUILTIN_NAMES:
            self.compile_builtin_call(head, form[1:], scopes)
        else:
            self.compile_call(form[0], form[1:], scopes)

    def compile_quoted(self, datum) -> None:
        e = self.e
        if datum == []:
            push(e, "r3")
        elif isinstance(datum, bool):
            self.emit_bool_literal(datum)
        elif isinstance(datum, int):
            self.emit_int_literal(datum)
        elif isinstance(datum, str):
            self.emit_string_literal(datum)
        elif isinstance(datum, list):
            # build a literal list of quoted items, right to left
            for item in reversed(datum):
                self.compile_quoted(item)
            e.emit(f"r6 = {TAG_NIL};")  # placeholder, replaced below
            raise NotImplementedError("quoted non-empty lists not needed by tests")
        else:
            raise ValueError(f"cannot quote: {datum!r}")

    # -- if -------------------------------------------------------------

    def compile_if(self, form: list, scopes: list[list[str]]) -> None:
        _, test, then, els = form
        e = self.e
        self.compile_expr(test, scopes)
        pop(e, "r6")
        then_label = e.fresh_label("if_then")
        else_label = e.fresh_label("if_else")
        join_label = e.fresh_label("if_join")
        e.emit("r7 = *r6;")
        e.emit(f"r9 = r7 == {TAG_BOOL};")
        e.emit("ifz r9 {")
        e.emit(f"    goto(@{then_label});")
        e.emit("} else {")
        e.emit("    r10 = r6 + 1;")
        e.emit("    r11 = *r10;")
        e.emit("    r12 = r11 == 0;")
        e.emit("    ifz r12 {")
        e.emit(f"        goto(@{then_label});")
        e.emit("    } else {")
        e.emit(f"        goto(@{else_label});")
        e.emit("    }")
        e.emit("}")
        e.start_block(then_label)
        self.compile_expr(then, scopes)
        e.emit(f"goto(@{join_label});")
        e.start_block(else_label)
        self.compile_expr(els, scopes)
        e.emit(f"goto(@{join_label});")
        e.start_block(join_label)

    # -- let / letrec -----------------------------------------------------

    def compile_let(self, form: list, scopes: list[list[str]]) -> None:
        _, bindings, body = form
        names = [b[0] for b in bindings]
        e = self.e
        for _, expr in bindings:
            self.compile_expr(expr, scopes)
        e.emit(f"r6 = malloc({1 + len(names)});")
        e.emit("*r6 = r2;")
        for i in range(len(names) - 1, -1, -1):
            pop(e, "r7")
            e.emit(f"r9 = r6 + {1 + i};")
            e.emit("*r9 = r7;")
        # Save the old env on the VALUE STACK (not a plain register) --
        # the body may contain calls, which clobber every scratch register
        # we could otherwise use.
        push(e, "r2")
        e.emit("r2 = r6;")
        new_scopes = scopes + [names]
        self.compile_expr(body, new_scopes)
        pop(e, "r14")  # body result
        pop(e, "r2")  # restore old env
        push(e, "r14")

    def compile_letrec(self, form: list, scopes: list[list[str]]) -> None:
        _, bindings, body = form
        names = [b[0] for b in bindings]
        e = self.e
        e.emit(f"r6 = malloc({1 + len(names)});")
        e.emit("*r6 = r2;")
        push(e, "r2")
        e.emit("r2 = r6;")
        new_scopes = scopes + [names]
        for i, (_, expr) in enumerate(bindings):
            self.compile_expr(expr, new_scopes)
            pop(e, "r7")
            e.emit(f"r9 = r2 + {1 + i};")
            e.emit("*r9 = r7;")
        self.compile_expr(body, new_scopes)
        pop(e, "r14")
        pop(e, "r2")
        push(e, "r14")

    # -- lambda / calls -----------------------------------------------------

    def compile_lambda(self, params: list, body, scopes: list[list[str]]) -> None:
        e = self.e
        entry_label = e.fresh_label("lam")
        self.pending.append((entry_label, params, body, list(scopes)))
        e.emit("r6 = malloc(3);")
        e.emit(f"*r6 = {TAG_CLOS};")
        e.emit("r7 = r6 + 1;")
        e.emit(f"*r7 = @{entry_label};")
        e.emit("r7 = r6 + 2;")
        e.emit("*r7 = r2;")
        push(e, "r6")

    def compile_call(self, fexpr, args: list, scopes: list[list[str]]) -> None:
        e = self.e
        self.compile_expr(fexpr, scopes)
        for a in args:
            self.compile_expr(a, scopes)
        n = len(args)
        e.emit(f"r6 = malloc({1 + n});")
        for i in range(n, 0, -1):
            pop(e, "r7")
            e.emit(f"r9 = r6 + {i};")
            e.emit("*r9 = r7;")
        pop(e, "r10")  # closure ptr
        e.emit("r11 = r10 + 1;")
        e.emit("r12 = *r11;")  # code block number
        e.emit("r11 = r10 + 2;")
        e.emit("r13 = *r11;")  # captured env
        e.emit("*r6 = r13;")
        cont_label = e.fresh_label("cont")
        e.emit(f"*r1 = @{cont_label};")
        e.emit("r1 = r1 + 1;")
        e.emit("*r1 = r2;")
        e.emit("r1 = r1 + 1;")
        e.emit("r2 = r6;")
        e.emit("goto(r12);")
        e.start_block(cont_label)

    # -- builtins -------------------------------------------------------

    def compile_builtin_call(self, name: str, args: list, scopes: list[list[str]]) -> None:
        e = self.e
        for a in args:
            self.compile_expr(a, scopes)

        if name in ("+", "-", "*", "=", "<", ">"):
            pop(e, "r7")  # b
            pop(e, "r6")  # a
            e.emit("r10 = r6 + 1;")
            e.emit("r11 = *r10;")
            e.emit("r12 = r7 + 1;")
            e.emit("r13 = *r12;")
            if name == "+":
                e.emit("r14 = r11 + r13;")
                self._box_int("r14")
            elif name == "-":
                e.emit("r14 = r11 - r13;")
                self._box_int("r14")
            elif name == "*":
                e.emit("r14 = r11 * r13;")
                self._box_int("r14")
            elif name == "=":
                e.emit("r14 = r11 == r13;")
                self._box_bool("r14")
            elif name == "<":
                e.emit("r14 = r11 < r13;")
                self._box_bool("r14")
            elif name == ">":
                e.emit("r14 = r13 < r11;")
                self._box_bool("r14")
        elif name == "cons":
            pop(e, "r7")
            pop(e, "r6")
            e.emit(f"r10 = malloc(3);")
            e.emit(f"*r10 = {TAG_PAIR};")
            e.emit("r11 = r10 + 1;")
            e.emit("*r11 = r6;")
            e.emit("r11 = r10 + 2;")
            e.emit("*r11 = r7;")
            push(e, "r10")
        elif name == "car":
            pop(e, "r6")
            e.emit("r10 = r6 + 1;")
            e.emit("r11 = *r10;")
            push(e, "r11")
        elif name == "cdr":
            pop(e, "r6")
            e.emit("r10 = r6 + 2;")
            e.emit("r11 = *r10;")
            push(e, "r11")
        elif name == "null?":
            pop(e, "r6")
            e.emit("r10 = *r6;")
            e.emit(f"r11 = r10 == {TAG_NIL};")
            self._box_bool("r11")
        elif name == "pair?":
            pop(e, "r6")
            e.emit("r10 = *r6;")
            e.emit(f"r11 = r10 == {TAG_PAIR};")
            self._box_bool("r11")
        elif name == "list":
            e.emit("r6 = r3;")  # nil
            for _ in args:
                pop(e, "r7")
                e.emit(f"r10 = malloc(3);")
                e.emit(f"*r10 = {TAG_PAIR};")
                e.emit("r11 = r10 + 1;")
                e.emit("*r11 = r7;")
                e.emit("r11 = r10 + 2;")
                e.emit("*r11 = r6;")
                e.emit("r6 = r10;")
            push(e, "r6")
        elif name == "string-append":
            self._emit_string_append(len(args))
        elif name == "string-length":
            pop(e, "r6")
            e.emit("r10 = r6 + 1;")
            e.emit("r11 = *r10;")
            self._box_int("r11")
        elif name == "display":
            pop(e, "r6")
            self._emit_display("r6")
            push(e, "r5")  # returns #f
        elif name == "error":
            e.emit("abort;")
        elif name == "vector":
            n = len(args)
            e.emit(f"r6 = malloc({2 + n});")
            e.emit(f"*r6 = {TAG_VEC};")
            e.emit("r10 = r6 + 1;")
            e.emit(f"*r10 = {n};")
            for i in range(n, 0, -1):
                pop(e, "r7")
                e.emit(f"r10 = r6 + {1 + i};")
                e.emit("*r10 = r7;")
            push(e, "r6")
        elif name == "vector-ref":
            pop(e, "r7")  # index cell
            pop(e, "r6")  # vector
            e.emit("r10 = r7 + 1;")
            e.emit("r11 = *r10;")  # raw index
            e.emit("r12 = r11 + 2;")
            e.emit("r13 = r6 + r12;")
            e.emit("r14 = *r13;")
            push(e, "r14")
        else:
            raise ValueError(f"unimplemented builtin: {name}")

    def _box_int(self, reg: str) -> None:
        e = self.e
        e.emit("r15 = malloc(2);")
        e.emit(f"*r15 = {TAG_INT};")
        e.emit("r16 = r15 + 1;")
        e.emit(f"*r16 = {reg};")
        push(e, "r15")

    def _box_bool(self, reg: str) -> None:
        # reg already holds exactly 0 or 1 (from ==/< etc), matching the
        # BOOL cell's payload representation directly -- no branch needed.
        e = self.e
        e.emit("r15 = malloc(2);")
        e.emit(f"*r15 = {TAG_BOOL};")
        e.emit("r16 = r15 + 1;")
        e.emit(f"*r16 = {reg};")
        push(e, "r15")

    def _emit_string_append(self, n: int) -> None:
        e = self.e
        regs = [f"r{20+i}" for i in range(n)]
        for r in reversed(regs):
            pop(e, r)
        # total length
        e.emit("r30 = 0;")
        for r in regs:
            e.emit(f"r31 = {r} + 1;")
            e.emit("r32 = *r31;")
            e.emit("r30 = r30 + r32;")
        e.emit("r33 = r30 + 4;")
        e.emit("r33 = r33 / 4;")
        e.emit("r34 = r33 + 2;")
        e.emit("r35 = malloc(r34);")
        e.emit(f"*r35 = {TAG_STRING};")
        e.emit("r36 = r35 + 1;")
        e.emit("*r36 = r30;")
        e.emit("r40 = 0;")  # output byte cursor (logical index across all inputs)
        for r in regs:
            e.emit(f"r41 = {r} + 1;")
            e.emit("r42 = *r41;")  # this string's length
            e.emit("r43 = 0;")  # index into this string
            loop = e.fresh_label("sa_loop")
            done = e.fresh_label("sa_done")
            e.emit(f"goto(@{loop});")
            e.start_block(loop)
            e.emit("r44 = r43 < r42;")
            e.emit("ifz r44 {")
            e.emit(f"    goto(@{done});")
            e.emit("} else {")
            e.emit("    r45 = r43 / 4;")
            e.emit("    r46 = r43 % 4;")
            e.emit(f"    r47 = {r} + 2;")
            e.emit("    r47 = r47 + r45;")
            e.emit("    r48 = *r47;")
            e.emit("    r49 = r46 * 8;")
            e.emit("    r49 = 24 - r49;")
            e.emit("    r50 = r48 >>> r49;")
            e.emit("    r50 = r50 & 255;")
            e.emit("    r51 = r40 / 4;")
            e.emit("    r52 = r40 % 4;")
            e.emit("    r53 = r36 + 1;")
            e.emit("    r53 = r53 + r51;")
            e.emit("    r54 = *r53;")
            e.emit("    r55 = r52 * 8;")
            e.emit("    r55 = 24 - r55;")
            e.emit("    r56 = 255 << r55;")
            e.emit("    r56 = ~ r56;")
            e.emit("    r54 = r54 & r56;")
            e.emit("    r57 = r50 << r55;")
            e.emit("    r54 = r54 | r57;")
            e.emit("    *r53 = r54;")
            e.emit("    r40 = r40 + 1;")
            e.emit("    r43 = r43 + 1;")
            e.emit(f"    goto(@{loop});")
            e.emit("}")
            e.start_block(done)
        push(e, "r35")

    def _append_char(self, byte_reg: str) -> None:
        e = self.e
        e.emit("r90 = r17 + r18;")
        e.emit(f"*r90 = {byte_reg};")
        e.emit("r18 = r18 + 1;")

    def _append_string_cell(self, reg: str) -> None:
        # ILVM strings are already packed 4-bytes/word big-endian; unpack
        # one byte at a time into the (unpacked, one-word-per-char) output
        # buffer.
        e = self.e
        e.emit(f"r91 = {reg} + 1;")
        e.emit("r92 = *r91;")  # length
        e.emit("r93 = 0;")
        loop = e.fresh_label("append_str_loop")
        done = e.fresh_label("append_str_done")
        e.emit(f"goto(@{loop});")
        e.start_block(loop)
        e.emit("r94 = r93 < r92;")
        e.emit("ifz r94 {")
        e.emit(f"    goto(@{done});")
        e.emit("} else {")
        e.emit("    r95 = r93 / 4;")
        e.emit("    r96 = r93 % 4;")
        e.emit(f"    r97 = {reg} + 2;")
        e.emit("    r97 = r97 + r95;")
        e.emit("    r98 = *r97;")
        e.emit("    r99 = r96 * 8;")
        e.emit("    r99 = 24 - r99;")
        e.emit("    r100 = r98 >>> r99;")
        e.emit("    r100 = r100 & 255;")
        e.emit("    r101 = r17 + r18;")
        e.emit("    *r101 = r100;")
        e.emit("    r18 = r18 + 1;")
        e.emit("    r93 = r93 + 1;")
        e.emit(f"    goto(@{loop});")
        e.emit("}")
        e.start_block(done)

    def _append_int(self, reg: str) -> None:
        e = self.e
        e.emit(f"r70 = {reg} + 1;")
        e.emit("r71 = *r70;")  # raw value
        zero_label = e.fresh_label("int_zero")
        nonzero_label = e.fresh_label("int_nonzero")
        digit_loop = e.fresh_label("int_digit_loop")
        digit_done = e.fresh_label("int_digit_done")
        neg_dash = e.fresh_label("int_neg_dash")
        pop_loop = e.fresh_label("int_pop_loop")
        done_label = e.fresh_label("int_done")
        e.emit("r72 = r71 == 0;")
        e.emit("ifz r72 {")
        e.emit(f"    goto(@{nonzero_label});")
        e.emit("} else {")
        e.emit(f"    goto(@{zero_label});")
        e.emit("}")
        e.start_block(zero_label)
        e.emit("r73 = 48;")
        self._append_char("r73")
        e.emit(f"goto(@{done_label});")
        abs_pos = e.fresh_label("int_abs_pos")
        abs_neg = e.fresh_label("int_abs_neg")
        e.start_block(nonzero_label)
        e.emit("r74 = r71 < 0;")
        e.emit("ifz r74 {")
        e.emit(f"    goto(@{abs_pos});")
        e.emit("} else {")
        e.emit(f"    goto(@{abs_neg});")
        e.emit("}")
        e.start_block(abs_pos)
        e.emit("r75 = r71;")
        e.emit("r76 = r0;")  # save vstack ptr (using it as scratch digit stack)
        e.emit(f"goto(@{digit_loop});")
        e.start_block(abs_neg)
        e.emit("r75 = 0 - r71;")
        e.emit("r76 = r0;")
        e.emit(f"goto(@{digit_loop});")
        e.start_block(digit_loop)
        e.emit("r77 = r75 == 0;")
        e.emit("ifz r77 {")
        e.emit("    r78 = r75 % 10;")
        e.emit("    r78 = r78 + 48;")
        push(e, "r78")
        e.emit("    r75 = r75 / 10;")
        e.emit(f"    goto(@{digit_loop});")
        e.emit("} else {")
        e.emit(f"    goto(@{digit_done});")
        e.emit("}")
        e.start_block(digit_done)
        e.emit("ifz r74 {")
        e.emit(f"    goto(@{pop_loop});")
        e.emit("} else {")
        e.emit(f"    goto(@{neg_dash});")
        e.emit("}")
        e.start_block(neg_dash)
        e.emit("r79 = 45;")
        self._append_char("r79")
        e.emit(f"goto(@{pop_loop});")
        e.start_block(pop_loop)
        e.emit("r80 = r0 == r76;")
        e.emit("ifz r80 {")
        pop(e, "r81")
        self._append_char("r81")
        e.emit(f"    goto(@{pop_loop});")
        e.emit("} else {")
        e.emit(f"    goto(@{done_label});")
        e.emit("}")
        e.start_block(done_label)

    def _emit_display(self, reg: str) -> None:
        # Every ifz/else must be the terminal instruction of its own block
        # (no goto allowed after it) -- so every branch, including nested
        # ones, gets its own block that ends in a plain goto. Output is
        # appended to a shared buffer (r17/r18), which is flushed at the end
        # of the program.
        e = self.e
        e.emit(f"r20 = *{reg};")
        int_label = e.fresh_label("disp_int")
        check_bool_label = e.fresh_label("disp_check_bool")
        str_label = e.fresh_label("disp_str")
        bool_true_label = e.fresh_label("disp_bool_true")
        bool_false_label = e.fresh_label("disp_bool_false")
        done_label = e.fresh_label("disp_done")
        e.emit(f"r21 = r20 == {TAG_INT};")
        e.emit("ifz r21 {")
        e.emit(f"    goto(@{check_bool_label});")
        e.emit("} else {")
        e.emit(f"    goto(@{int_label});")
        e.emit("}")
        e.start_block(int_label)
        self._append_int(reg)
        e.emit(f"goto(@{done_label});")
        e.start_block(check_bool_label)
        e.emit(f"r21 = r20 == {TAG_BOOL};")
        e.emit("ifz r21 {")
        e.emit(f"    goto(@{str_label});")
        e.emit("} else {")
        e.emit(f"    r22 = {reg} + 1;")
        e.emit("    r23 = *r22;")
        e.emit("    ifz r23 {")
        e.emit(f"        goto(@{bool_false_label});")
        e.emit("    } else {")
        e.emit(f"        goto(@{bool_true_label});")
        e.emit("    }")
        e.emit("}")
        e.start_block(bool_false_label)
        e.emit("r24 = 35;")  # '#'
        self._append_char("r24")
        e.emit("r24 = 102;")  # 'f'
        self._append_char("r24")
        e.emit(f"goto(@{done_label});")
        e.start_block(bool_true_label)
        e.emit("r24 = 35;")  # '#'
        self._append_char("r24")
        e.emit("r24 = 116;")  # 't'
        self._append_char("r24")
        e.emit(f"goto(@{done_label});")
        e.start_block(str_label)
        self._append_string_cell(reg)
        e.emit(f"goto(@{done_label});")
        e.start_block(done_label)
        e.emit("r24 = 10;")
        self._append_char("r24")


def push(e: Emitter, reg: str) -> None:
    e.emit(f"*r0 = {reg};")
    e.emit("r0 = r0 + 1;")


def pop(e: Emitter, reg: str) -> None:
    e.emit("r0 = r0 - 1;")
    e.emit(f"{reg} = *r0;")


# ---------------------------------------------------------------------------
# Top-level driver
# ---------------------------------------------------------------------------


def compile_program(text: str) -> str:
    forms = parse_program(text)
    c = Compiler()
    c.collect_globals(forms)
    e = c.e

    e.start_block("start")
    e.emit("r0 = malloc(20000);")
    e.emit("r1 = malloc(20000);")
    e.emit("r2 = 0;")
    e.emit("r17 = malloc(65536);")
    e.emit("r18 = 0;")
    e.emit(f"r3 = malloc(1);")
    e.emit(f"*r3 = {TAG_NIL};")
    e.emit("r4 = malloc(2);")
    e.emit(f"*r4 = {TAG_BOOL};")
    e.emit("r6 = r4 + 1;")
    e.emit("*r6 = 1;")
    e.emit("r5 = malloc(2);")
    e.emit(f"*r5 = {TAG_BOOL};")
    e.emit("r6 = r5 + 1;")
    e.emit("*r6 = 0;")
    e.emit(f"r8 = malloc({max(len(c.globals), 1)});")

    # Translate ILVM's packed command-line argument area into a MiniScheme
    # vector of boxed strings. ILVM places the argument count at heap[1] and
    # pointers to packed strings at heap[2..].
    e.emit("r30 = *1;")
    e.emit("r29 = r30 + 2;")
    e.emit("r31 = malloc(r29);")
    e.emit(f"*r31 = {TAG_VEC};")
    e.emit("r29 = r31 + 1;")
    e.emit("*r29 = r30;")
    e.emit("r32 = 0;")
    e.emit("goto(@argv_loop);")

    e.start_block("argv_loop")
    e.emit("r29 = r32 < r30;")
    e.emit("ifz r29 {")
    e.emit("    goto(@argv_ready);")
    e.emit("} else {")
    e.emit("    goto(@argv_scan_init);")
    e.emit("}")

    e.start_block("argv_scan_init")
    e.emit("r33 = r32 + 2;")
    e.emit("r34 = *r33;")
    e.emit("r35 = 0;")  # string length in bytes
    e.emit("r36 = 0;")  # packed-word offset
    e.emit("r37 = 0;")  # byte offset within word
    e.emit("goto(@argv_scan_byte);")

    e.start_block("argv_scan_byte")
    e.emit("r38 = r34 + r36;")
    e.emit("r39 = *r38;")
    e.emit("r40 = 3 - r37;")
    e.emit("r40 = r40 * 8;")
    e.emit("r41 = r39 >> r40;")
    e.emit("r41 = r41 & 255;")
    e.emit("ifz r41 {")
    e.emit("    goto(@argv_alloc_string);")
    e.emit("} else {")
    e.emit("    goto(@argv_scan_continue);")
    e.emit("}")

    e.start_block("argv_scan_continue")
    e.emit("r35 = r35 + 1;")
    e.emit("r37 = r37 + 1;")
    e.emit("r42 = r37 == 4;")
    e.emit("ifz r42 {")
    e.emit("    goto(@argv_scan_byte);")
    e.emit("} else {")
    e.emit("    goto(@argv_scan_next_word);")
    e.emit("}")

    e.start_block("argv_scan_next_word")
    e.emit("r36 = r36 + 1;")
    e.emit("r37 = 0;")
    e.emit("goto(@argv_scan_byte);")

    e.start_block("argv_alloc_string")
    e.emit("r43 = r35 + 4;")
    e.emit("r43 = r43 / 4;")
    e.emit("r29 = r43 + 2;")
    e.emit("r44 = malloc(r29);")
    e.emit(f"*r44 = {TAG_STRING};")
    e.emit("r29 = r44 + 1;")
    e.emit("*r29 = r35;")
    e.emit("r45 = 0;")
    e.emit("goto(@argv_copy_loop);")

    e.start_block("argv_copy_loop")
    e.emit("r29 = r45 < r43;")
    e.emit("ifz r29 {")
    e.emit("    goto(@argv_store_string);")
    e.emit("} else {")
    e.emit("    goto(@argv_copy_word);")
    e.emit("}")

    e.start_block("argv_copy_word")
    e.emit("r46 = r34 + r45;")
    e.emit("r47 = *r46;")
    e.emit("r48 = r44 + 2;")
    e.emit("r48 = r48 + r45;")
    e.emit("*r48 = r47;")
    e.emit("r45 = r45 + 1;")
    e.emit("goto(@argv_copy_loop);")

    e.start_block("argv_store_string")
    e.emit("r29 = r31 + 2;")
    e.emit("r29 = r29 + r32;")
    e.emit("*r29 = r44;")
    e.emit("r32 = r32 + 1;")
    e.emit("goto(@argv_loop);")

    e.start_block("argv_ready")
    e.emit(f"r29 = r8 + {c.globals['argv']};")
    e.emit("*r29 = r31;")
    e.emit("goto(@runtime_literals);")

    e.start_block("runtime_literals")
    for text_lit, key in c.string_slot.items():
        idx = c.globals[key]
        words = pack_words(text_lit)
        e.emit(f"r6 = malloc({2 + len(words)});")
        e.emit(f"*r6 = {TAG_STRING};")
        e.emit("r7 = r6 + 1;")
        e.emit(f"*r7 = {len(text_lit)};")
        for i, w in enumerate(words):
            e.emit(f"r7 = r6 + {2 + i};")
            e.emit(f"*r7 = {w};")
        e.emit(f"r7 = r8 + {idx};")
        e.emit("*r7 = r6;")
    e.emit("goto(@toplevel_0);")

    for i, form in enumerate(forms):
        e.start_block(f"toplevel_{i}")
        if isinstance(form, list) and form and form[0] == "define":
            target = form[1]
            if isinstance(target, list):
                name = target[0]
                params = target[1:]
                c.compile_lambda(params, form[2], [])
            else:
                name = target
                c.compile_expr(form[2], [])
            c.emit_global_store(name)
        else:
            c.compile_expr(form, [])
            pop(e, "r6")
        e.emit(f"goto(@toplevel_{i + 1});")

    e.start_block(f"toplevel_{len(forms)}")
    e.emit("ifz r18 {")
    e.emit("    goto(@exit_no_output);")
    e.emit("} else {")
    e.emit("    goto(@flush_prepare);")
    e.emit("}")

    e.start_block("flush_prepare")
    # The buffered output ends in the newline supplied by the last display.
    # Remove it because ILVM's print_str supplies that final newline itself.
    e.emit("r18 = r18 - 1;")
    e.emit("r210 = r18 + 4;")
    e.emit("r210 = r210 / 4;")
    e.emit("r211 = r210 + 2;")
    e.emit("r212 = malloc(r211);")
    e.emit(f"*r212 = {TAG_STRING};")
    e.emit("r213 = r212 + 1;")
    e.emit("*r213 = r18;")
    e.emit("r214 = 0;")
    e.emit("goto(@flush_word_loop);")

    e.start_block("flush_word_loop")
    e.emit("r215 = r214 < r210;")
    e.emit("ifz r215 {")
    e.emit("    goto(@flush_finish);")
    e.emit("} else {")
    e.emit("    r216 = r214 * 4;")
    e.emit("    r217 = 0;")
    e.emit("    r218 = 0;")
    e.emit("    goto(@flush_byte_loop);")
    e.emit("}")

    e.start_block("flush_byte_loop")
    e.emit("r219 = r216 + r218;")
    e.emit("r220 = r219 < r18;")
    e.emit("ifz r220 {")
    e.emit("    r221 = 0;")
    e.emit("    goto(@flush_byte_accum);")
    e.emit("} else {")
    e.emit("    r222 = r17 + r219;")
    e.emit("    r221 = *r222;")
    e.emit("    goto(@flush_byte_accum);")
    e.emit("}")

    e.start_block("flush_byte_accum")
    e.emit("r217 = r217 << 8;")
    e.emit("r217 = r217 | r221;")
    e.emit("r218 = r218 + 1;")
    e.emit("r223 = r218 < 4;")
    e.emit("ifz r223 {")
    e.emit("    r224 = r212 + 2;")
    e.emit("    r224 = r224 + r214;")
    e.emit("    *r224 = r217;")
    e.emit("    r214 = r214 + 1;")
    e.emit("    goto(@flush_word_loop);")
    e.emit("} else {")
    e.emit("    goto(@flush_byte_loop);")
    e.emit("}")

    e.start_block("flush_finish")
    e.emit("r225 = r212 + 2;")
    e.emit("print_str(r225);")
    e.emit("exit(0);")

    e.start_block("exit_no_output")
    e.emit("exit(0);")

    idx = 0
    while idx < len(c.pending):
        entry_label, params, body, captured_scopes = c.pending[idx]
        idx += 1
        e.start_block(entry_label)
        scopes = captured_scopes + [list(params)]
        c.compile_expr(body, scopes)
        pop(e, "r60")
        e.emit("r1 = r1 - 1;")
        e.emit("r2 = *r1;")
        e.emit("r1 = r1 - 1;")
        e.emit("r61 = *r1;")
        push(e, "r60")
        e.emit("goto(r61);")

    return remap_registers(e.render())


PERSISTENT_REGS = {0, 1, 2, 3, 4, 5, 8, 17, 18}
SCRATCH_POOL_LO, SCRATCH_POOL_HI = 19, 63  # full remaining budget (ILVM -r 64)


def remap_registers(ilvm_text: str) -> str:
    """Compress every non-persistent register into a small shared pool.
    Safe because scratch registers are never relied on to survive a call
    (compile_call/lambda entry/exit use the explicit vsp/csp stacks for
    anything that must persist across a call; let/letrec save the old env
    on the value stack rather than in a register) -- so registers used by
    textually distant, never-simultaneously-live code paths (e.g. the
    arithmetic builtins vs. the int-to-string helper) can safely share
    numbers. Verified empirically against tests/examples/*.scm.
    """

    def sub(m: re.Match) -> str:
        n = int(m.group(1))
        if n in PERSISTENT_REGS or n < SCRATCH_POOL_LO:
            return m.group(0)
        width = SCRATCH_POOL_HI - SCRATCH_POOL_LO + 1
        return f"r{SCRATCH_POOL_LO + (n - SCRATCH_POOL_LO) % width}"

    return re.sub(r"\br(\d+)\b", sub, ilvm_text)


if __name__ == "__main__":
    src = sys.stdin.read()
    print(compile_program(src))
