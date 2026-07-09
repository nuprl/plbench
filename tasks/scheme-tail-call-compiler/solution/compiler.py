#!/usr/bin/env python3
"""Oracle MiniScheme-to-MiniScheme CPS compiler.

Every CPS expression installs a zero-argument thunk in a mutable `next`
variable. A generated `while` loop invokes one thunk per iteration, and the
halt continuation stops it through ordinary `set!`. The evaluator needs no
knowledge of the trampoline protocol.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable


class CompileError(Exception):
    pass


@dataclass(frozen=True)
class Sym:
    name: str


@dataclass(frozen=True)
class Vec:
    items: tuple[object, ...]


S = Sym
Expr = object


BUILTINS = {
    "+", "-", "*", "/", "=", "<", ">", "<=", ">=",
    "number?", "integer?", "float?", "boolean?", "string?", "symbol?",
    "procedure?", "null?", "pair?", "list?", "vector?", "not", "eq?",
    "equal?", "cons", "car", "cdr", "list", "length", "append",
    "list-ref", "vector", "vector-length", "vector-ref", "string-length",
    "string-append", "string-ref", "string->symbol", "symbol->string",
    "apply", "display", "error",
}


def tokenize(source: str) -> list[object]:
    tokens: list[object] = []
    i = 0
    n = len(source)
    delimiters = set("()'\"; \t\r\n")
    while i < n:
        c = source[i]
        if c.isspace():
            i += 1
        elif c == ";":
            while i < n and source[i] != "\n":
                i += 1
        elif source.startswith("#(", i):
            tokens.append("#(")
            i += 2
        elif c in "()'":
            tokens.append(c)
            i += 1
        elif c == '"':
            i += 1
            chars: list[str] = []
            while i < n and source[i] != '"':
                if source[i] == "\\":
                    i += 1
                    if i >= n:
                        raise CompileError("unterminated string escape")
                    escapes = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
                    if source[i] not in escapes:
                        raise CompileError(f"bad string escape: \\{source[i]}")
                    chars.append(escapes[source[i]])
                else:
                    chars.append(source[i])
                i += 1
            if i >= n:
                raise CompileError("unterminated string")
            i += 1
            tokens.append(("string", "".join(chars)))
        else:
            start = i
            while i < n and source[i] not in delimiters:
                i += 1
            if start == i:
                raise CompileError(f"unexpected character {source[i]!r}")
            tokens.append(source[start:i])
    return tokens


def atom(token: str) -> Expr:
    if token == "#t":
        return True
    if token == "#f":
        return False
    try:
        if "." in token:
            return float(token)
        return int(token)
    except ValueError:
        return S(token)


def parse(source: str) -> list[Expr]:
    tokens = tokenize(source)
    pos = 0

    def datum() -> Expr:
        nonlocal pos
        if pos >= len(tokens):
            raise CompileError("unexpected end of input")
        token = tokens[pos]
        pos += 1
        if token == "(":
            values: list[Expr] = []
            while pos < len(tokens) and tokens[pos] != ")":
                values.append(datum())
            if pos >= len(tokens):
                raise CompileError("missing )")
            pos += 1
            return values
        if token == "#(":
            values: list[Expr] = []
            while pos < len(tokens) and tokens[pos] != ")":
                values.append(datum())
            if pos >= len(tokens):
                raise CompileError("missing ) after vector")
            pos += 1
            return Vec(tuple(values))
        if token == "'":
            return [S("quote"), datum()]
        if token == ")":
            raise CompileError("unexpected )")
        if isinstance(token, tuple) and token[0] == "string":
            return token[1]
        assert isinstance(token, str)
        return atom(token)

    forms: list[Expr] = []
    while pos < len(tokens):
        forms.append(datum())
    return forms


def emit(expr: Expr) -> str:
    if isinstance(expr, Sym):
        return expr.name
    if expr is True:
        return "#t"
    if expr is False:
        return "#f"
    if isinstance(expr, int):
        return str(expr)
    if isinstance(expr, float):
        text = repr(expr)
        return text if "." in text else text + ".0"
    if isinstance(expr, str):
        escaped = (
            expr.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\n", "\\n")
            .replace("\t", "\\t")
        )
        return f'"{escaped}"'
    if isinstance(expr, Vec):
        return "#(" + " ".join(emit(x) for x in expr.items) + ")"
    if isinstance(expr, list):
        return "(" + " ".join(emit(x) for x in expr) + ")"
    raise CompileError(f"cannot print AST node: {expr!r}")


def is_form(expr: Expr, name: str) -> bool:
    return isinstance(expr, list) and bool(expr) and expr[0] == S(name)


def flatten_toplevel(forms: Iterable[Expr]) -> list[Expr]:
    answer: list[Expr] = []
    for form in forms:
        if is_form(form, "begin"):
            answer.extend(flatten_toplevel(form[1:]))
        else:
            answer.append(form)
    return answer


def symbols(expr: Expr) -> set[str]:
    if isinstance(expr, Sym):
        return {expr.name}
    if isinstance(expr, Vec):
        result: set[str] = set()
        for item in expr.items:
            result.update(symbols(item))
        return result
    if isinstance(expr, list):
        result: set[str] = set()
        for item in expr:
            result.update(symbols(item))
        return result
    return set()


class Compiler:
    def __init__(self, forms: list[Expr]):
        self.forms = flatten_toplevel(forms)
        self.used: set[str] = set()
        for form in self.forms:
            self.used.update(symbols(form))
        self.serial = 0
        self.top_names = self._top_names()
        self.next_step = self.fresh("next")
        self.running = self.fresh("running")
        self.result = self.fresh("result")
        self.halt = self.fresh("halt")

    def fresh(self, purpose: str) -> Sym:
        while True:
            name = f"$cps-{purpose}-{self.serial}"
            self.serial += 1
            if name not in self.used:
                self.used.add(name)
                return S(name)

    def _top_names(self) -> set[str]:
        names: set[str] = set()
        for form in self.forms:
            if not is_form(form, "define") or len(form) != 3:
                continue
            target = form[1]
            if isinstance(target, Sym):
                names.add(target.name)
            elif isinstance(target, list) and target and isinstance(target[0], Sym):
                names.add(target[0].name)
        return names

    def schedule_call(self, proc: Expr, args: list[Expr]) -> Expr:
        thunk = [S("lambda"), [], [proc, *args]]
        return [S("set!"), self.next_step, thunk]

    def pass_value(self, value: Expr, k: Expr) -> Expr:
        return self.schedule_call(k, [value])

    def continuation(self, name: Sym, body: Expr) -> Expr:
        return [S("lambda"), [name], body]

    def cps_values(
        self,
        exprs: list[Expr],
        scope: set[str],
        finish: Callable[[list[Expr]], Expr],
        values: list[Expr] | None = None,
    ) -> Expr:
        values = [] if values is None else values
        if not exprs:
            return finish(values)
        value_name = self.fresh("value")
        rest = self.cps_values(exprs[1:], scope, finish, [*values, value_name])
        return self.cps(exprs[0], self.continuation(value_name, rest), scope)

    def direct_value(self, expr: Expr, scope: set[str]) -> Expr:
        if is_form(expr, "lambda"):
            return self.cps_lambda(expr, scope)
        if is_form(expr, "quote") and len(expr) == 2:
            return expr
        if isinstance(expr, (bool, int, float, str, Sym)):
            return expr
        raise CompileError(
            "Oracle supports only constants, variables, quotes, and lambdas "
            "as direct letrec/top-level initializers"
        )

    def cps_lambda(self, expr: Expr, scope: set[str]) -> Expr:
        if not (isinstance(expr, list) and len(expr) == 3 and isinstance(expr[1], list)):
            raise CompileError("bad lambda")
        params = expr[1]
        if not all(isinstance(p, Sym) for p in params):
            raise CompileError("lambda parameters must be symbols")
        k = self.fresh("k")
        local = scope | {p.name for p in params} | {k.name}
        return [S("lambda"), [*params, k], self.cps(expr[2], k, local)]

    def cps_sequence(self, exprs: list[Expr], k: Expr, scope: set[str]) -> Expr:
        if not exprs:
            return self.pass_value(False, k)
        if len(exprs) == 1:
            return self.cps(exprs[0], k, scope)
        ignored = self.fresh("ignored")
        return self.cps(
            exprs[0],
            self.continuation(ignored, self.cps_sequence(exprs[1:], k, scope)),
            scope,
        )

    def cps_and(self, exprs: list[Expr], k: Expr, scope: set[str]) -> Expr:
        if not exprs:
            return self.pass_value(True, k)
        if len(exprs) == 1:
            return self.cps(exprs[0], k, scope)
        value = self.fresh("and")
        body = [
            S("if"),
            value,
            self.cps_and(exprs[1:], k, scope),
            self.pass_value(value, k),
        ]
        return self.cps(exprs[0], self.continuation(value, body), scope)

    def cps_or(self, exprs: list[Expr], k: Expr, scope: set[str]) -> Expr:
        if not exprs:
            return self.pass_value(False, k)
        if len(exprs) == 1:
            return self.cps(exprs[0], k, scope)
        value = self.fresh("or")
        body = [
            S("if"),
            value,
            self.pass_value(value, k),
            self.cps_or(exprs[1:], k, scope),
        ]
        return self.cps(exprs[0], self.continuation(value, body), scope)

    def cond_to_if(self, clauses: list[Expr]) -> Expr:
        if not clauses:
            return [S("error"), "cond: no clause matched"]
        clause = clauses[0]
        if not (isinstance(clause, list) and len(clause) == 2):
            raise CompileError("bad cond clause")
        if clause[0] == S("else"):
            return clause[1]
        return [S("if"), clause[0], clause[1], self.cond_to_if(clauses[1:])]

    def cps_application(self, expr: list[Expr], k: Expr, scope: set[str]) -> Expr:
        head, args = expr[0], expr[1:]
        primitive = (
            isinstance(head, Sym)
            and head.name in BUILTINS
            and head.name not in scope
        )
        if primitive and head == S("apply"):
            if len(args) != 2:
                raise CompileError("apply requires two arguments")
            if isinstance(args[0], Sym) and args[0].name in BUILTINS and args[0].name not in scope:
                list_value = self.fresh("apply-args")
                call = [S("apply"), args[0], list_value]
                return self.cps(
                    args[1],
                    self.continuation(list_value, self.pass_value(call, k)),
                    scope,
                )

            def finish_apply(values: list[Expr]) -> Expr:
                proc, arg_list = values
                with_k = [S("append"), arg_list, [S("list"), k]]
                return self.schedule_call(S("apply"), [proc, with_k])

            return self.cps_values(args, scope, finish_apply)

        if primitive:
            return self.cps_values(
                args,
                scope,
                lambda values: self.pass_value([head, *values], k),
            )

        def with_proc(proc: Expr) -> Expr:
            return self.cps_values(
                args,
                scope,
                lambda values: self.schedule_call(proc, [*values, k]),
            )

        proc_name = self.fresh("proc")
        return self.cps(head, self.continuation(proc_name, with_proc(proc_name)), scope)

    def cps(self, expr: Expr, k: Expr, scope: set[str]) -> Expr:
        if isinstance(expr, (bool, int, float, str, Sym)) or isinstance(expr, Vec):
            return self.pass_value(expr, k)
        if not isinstance(expr, list) or not expr:
            raise CompileError("empty list is not an expression")
        if is_form(expr, "quote"):
            if len(expr) != 2:
                raise CompileError("quote requires one argument")
            return self.pass_value(expr, k)
        if is_form(expr, "lambda"):
            return self.pass_value(self.cps_lambda(expr, scope), k)
        if is_form(expr, "if"):
            if len(expr) != 4:
                raise CompileError("if requires three arguments")
            test = self.fresh("test")
            branches = [
                S("if"), test,
                self.cps(expr[2], k, scope),
                self.cps(expr[3], k, scope),
            ]
            return self.cps(expr[1], self.continuation(test, branches), scope)
        if is_form(expr, "begin"):
            return self.cps_sequence(expr[1:], k, scope)
        if is_form(expr, "and"):
            return self.cps_and(expr[1:], k, scope)
        if is_form(expr, "or"):
            return self.cps_or(expr[1:], k, scope)
        if is_form(expr, "cond"):
            return self.cps(self.cond_to_if(expr[1:]), k, scope)
        if is_form(expr, "let"):
            if len(expr) != 3 or not isinstance(expr[1], list):
                raise CompileError("bad let")
            names: list[Expr] = []
            values: list[Expr] = []
            for binding in expr[1]:
                if not (isinstance(binding, list) and len(binding) == 2 and isinstance(binding[0], Sym)):
                    raise CompileError("bad let binding")
                names.append(binding[0])
                values.append(binding[1])
            return self.cps([[S("lambda"), names, expr[2]], *values], k, scope)
        if is_form(expr, "letrec"):
            if len(expr) != 3 or not isinstance(expr[1], list):
                raise CompileError("bad letrec")
            names: list[Sym] = []
            for binding in expr[1]:
                if not (isinstance(binding, list) and len(binding) == 2 and isinstance(binding[0], Sym)):
                    raise CompileError("bad letrec binding")
                names.append(binding[0])
            local = scope | {name.name for name in names}
            bindings = [
                [binding[0], self.direct_value(binding[1], local)]
                for binding in expr[1]
            ]
            return [S("letrec"), bindings, self.cps(expr[2], k, local)]
        if is_form(expr, "set!"):
            if len(expr) != 3 or not isinstance(expr[1], Sym):
                raise CompileError("bad set!")
            assigned = self.fresh("assigned")
            after_assignment = [
                S("begin"),
                [S("set!"), expr[1], assigned],
                self.pass_value(assigned, k),
            ]
            return self.cps(
                expr[2], self.continuation(assigned, after_assignment), scope
            )
        if is_form(expr, "while"):
            if len(expr) != 3:
                raise CompileError("bad while")
            loop = self.fresh("while-loop")
            previous = self.fresh("while-result")
            test = self.fresh("while-test")
            body_result = self.fresh("while-body")
            local = scope | {loop.name, previous.name}
            next_iteration = self.continuation(
                body_result, self.schedule_call(loop, [body_result])
            )
            decide = [
                S("if"),
                test,
                self.cps(expr[2], next_iteration, local),
                self.pass_value(previous, k),
            ]
            loop_body = self.cps(
                expr[1], self.continuation(test, decide), local
            )
            return [
                S("letrec"),
                [[loop, [S("lambda"), [previous], loop_body]]],
                self.schedule_call(loop, [False]),
            ]
        if is_form(expr, "define"):
            raise CompileError("define is only valid at top level")
        return self.cps_application(expr, k, scope)

    def compile_define(self, form: list[Expr]) -> Expr:
        if len(form) != 3:
            raise CompileError("bad define")
        target, value = form[1], form[2]
        scope = set(self.top_names)
        if isinstance(target, list) and target and isinstance(target[0], Sym):
            name = target[0]
            params = target[1:]
            if not all(isinstance(p, Sym) for p in params):
                raise CompileError("define parameters must be symbols")
            k = self.fresh("k")
            local = scope | {p.name for p in params} | {k.name}
            return [S("define"), [name, *params, k], self.cps(value, k, local)]
        if isinstance(target, Sym):
            return [S("define"), target, self.direct_value(value, scope)]
        raise CompileError("bad define target")

    def compile(self) -> str:
        halt_arg = self.fresh("answer")
        output: list[Expr] = [
            [S("define"), self.next_step, False],
            [S("define"), self.running, False],
            [S("define"), self.result, False],
            [
                S("define"),
                [self.halt, halt_arg],
                [
                    S("begin"),
                    [S("set!"), self.result, halt_arg],
                    [S("set!"), self.running, False],
                    halt_arg,
                ],
            ]
        ]

        for form in self.forms:
            if is_form(form, "define"):
                output.append(self.compile_define(form))
            else:
                step = self.fresh("step")
                output.append(
                    [
                        S("begin"),
                        [S("set!"), self.running, True],
                        [S("set!"), self.result, False],
                        [
                            S("set!"),
                            self.next_step,
                            [
                                S("lambda"),
                                [],
                                self.cps(form, self.halt, set(self.top_names)),
                            ],
                        ],
                        [
                            S("while"),
                            self.running,
                            [
                                S("let"),
                                [[step, self.next_step]],
                                [
                                    S("begin"),
                                    [S("set!"), self.next_step, False],
                                    [step],
                                ],
                            ],
                        ],
                        self.result,
                    ]
                )
        return "\n".join(emit(form) for form in output) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: compiler INPUT.scm OUTPUT.scm", file=sys.stderr)
        return 2
    source_path = Path(argv[1])
    output_path = Path(argv[2])
    try:
        forms = parse(source_path.read_text())
        compiled = Compiler(forms).compile()
        output_path.write_text(compiled)
        return 0
    except (OSError, CompileError) as error:
        print(f"compiler: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
