#!/usr/bin/env python3
"""Trusted parser, elaborator, and guarded evaluator for the task's GTLC."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any as PyAny


class ParseError(ValueError):
    pass


class StaticError(ValueError):
    pass


class CastError(RuntimeError):
    pass


class Diverged(RuntimeError):
    pass


@dataclass(frozen=True)
class Type:
    tag: str
    left: "Type | None" = None
    right: "Type | None" = None

    def __str__(self) -> str:
        if self.tag != "arr":
            return self.tag
        assert self.left is not None and self.right is not None
        lhs = f"({self.left})" if self.left.tag == "arr" else str(self.left)
        return f"{lhs} -> {self.right}"


INT = Type("int")
BOOL = Type("bool")
ANY = Type("any")


def Arr(left: Type, right: Type) -> Type:
    return Type("arr", left, right)


@dataclass(frozen=True)
class Lit:
    value: int | bool


@dataclass(frozen=True)
class Var:
    name: str


@dataclass(frozen=True)
class Fun:
    name: str
    annotation: Type | None
    body: "Expr"


@dataclass(frozen=True)
class App:
    fn: "Expr"
    arg: "Expr"


@dataclass(frozen=True)
class Bin:
    op: str
    left: "Expr"
    right: "Expr"


@dataclass(frozen=True)
class If:
    cond: "Expr"
    then: "Expr"
    otherwise: "Expr"


@dataclass(frozen=True)
class Let:
    name: str
    value: "Expr"
    body: "Expr"


@dataclass(frozen=True)
class Ann:
    expr: "Expr"
    typ: Type


Expr = Lit | Var | Fun | App | Bin | If | Let | Ann


@dataclass(frozen=True)
class Token:
    kind: str
    text: str
    pos: int


KEYWORDS = {
    "fun", "if", "then", "else", "let", "in", "true", "false",
    "int", "bool", "any",
}


def tokenize(src: str) -> list[Token]:
    if len(src) > 1_000_000:
        raise ParseError("program is too large")
    out: list[Token] = []
    i = 0
    while i < len(src):
        c = src[i]
        if c.isspace():
            i += 1
            continue
        if src.startswith("//", i):
            nl = src.find("\n", i + 2)
            i = len(src) if nl < 0 else nl + 1
            continue
        if src.startswith("->", i):
            out.append(Token("->", "->", i))
            i += 2
            continue
        if c in "().:+*=":
            out.append(Token(c, c, i))
            i += 1
            continue
        if c == "-" and i + 1 < len(src) and src[i + 1].isdigit() or c.isdigit():
            j = i + (1 if c == "-" else 0)
            while j < len(src) and src[j].isdigit():
                j += 1
            out.append(Token("INT", src[i:j], i))
            i = j
            continue
        if c.isascii() and (c.isalpha() or c == "_"):
            j = i + 1
            while j < len(src) and src[j].isascii() and (src[j].isalnum() or src[j] == "_"):
                j += 1
            text = src[i:j]
            out.append(Token(text if text in KEYWORDS else "ID", text, i))
            i = j
            continue
        raise ParseError(f"unexpected character {c!r} at byte {i}")
    out.append(Token("EOF", "", len(src)))
    return out


class Parser:
    def __init__(self, src: str):
        self.tokens = tokenize(src)
        self.i = 0

    def peek(self, kind: str | None = None) -> Token | bool:
        tok = self.tokens[self.i]
        return tok if kind is None else tok.kind == kind

    def take(self, kind: str) -> Token:
        tok = self.tokens[self.i]
        if tok.kind != kind:
            raise ParseError(f"expected {kind!r} at byte {tok.pos}, found {tok.text!r}")
        self.i += 1
        return tok

    def parse(self) -> Expr:
        result = self.expr()
        self.take("EOF")
        return result

    def typ(self) -> Type:
        left = self.typ_atom()
        if self.peek("->"):
            self.take("->")
            return Arr(left, self.typ())
        return left

    def typ_atom(self) -> Type:
        if self.peek("int"):
            self.take("int")
            return INT
        if self.peek("bool"):
            self.take("bool")
            return BOOL
        if self.peek("any"):
            self.take("any")
            return ANY
        if self.peek("("):
            self.take("(")
            result = self.typ()
            self.take(")")
            return result
        tok = self.peek()
        assert isinstance(tok, Token)
        raise ParseError(f"expected type at byte {tok.pos}, found {tok.text!r}")

    def expr(self) -> Expr:
        if self.peek("fun"):
            self.take("fun")
            name = self.take("ID").text
            annotation = None
            if self.peek(":"):
                self.take(":")
                annotation = self.typ()
            self.take(".")
            return Fun(name, annotation, self.expr())
        if self.peek("if"):
            self.take("if")
            cond = self.expr()
            self.take("then")
            yes = self.expr()
            self.take("else")
            no = self.expr()
            return If(cond, yes, no)
        if self.peek("let"):
            self.take("let")
            name = self.take("ID").text
            self.take("=")
            value = self.expr()
            self.take("in")
            return Let(name, value, self.expr())
        result = self.add()
        if self.peek(":"):
            self.take(":")
            result = Ann(result, self.typ())
        return result

    def add(self) -> Expr:
        result = self.mul()
        while self.peek("+"):
            self.take("+")
            result = Bin("+", result, self.mul())
        return result

    def mul(self) -> Expr:
        result = self.app()
        while self.peek("*"):
            self.take("*")
            result = Bin("*", result, self.app())
        return result

    def app(self) -> Expr:
        result = self.atom()
        while self.starts_atom():
            result = App(result, self.atom())
        return result

    def starts_atom(self) -> bool:
        tok = self.tokens[self.i].kind
        return tok in {"INT", "true", "false", "ID", "("}

    def atom(self) -> Expr:
        if self.peek("INT"):
            return Lit(int(self.take("INT").text))
        if self.peek("true"):
            self.take("true")
            return Lit(True)
        if self.peek("false"):
            self.take("false")
            return Lit(False)
        if self.peek("ID"):
            return Var(self.take("ID").text)
        if self.peek("("):
            self.take("(")
            result = self.expr()
            self.take(")")
            return result
        tok = self.peek()
        assert isinstance(tok, Token)
        raise ParseError(f"expected expression at byte {tok.pos}, found {tok.text!r}")


def parse(src: str) -> Expr:
    return Parser(src).parse()


def consistent(a: Type, b: Type) -> bool:
    if a == ANY or b == ANY:
        return True
    if a.tag == "arr" and b.tag == "arr":
        assert a.left and a.right and b.left and b.right
        return consistent(a.left, b.left) and consistent(a.right, b.right)
    return a == b


def type_leq(less: Type, more: Type) -> bool:
    if less == ANY:
        return True
    if less.tag == "arr" and more.tag == "arr":
        assert less.left and less.right and more.left and more.right
        return type_leq(less.left, more.left) and type_leq(less.right, more.right)
    return less == more


def branch_type(a: Type, b: Type) -> Type:
    if a == b:
        return a
    if a == ANY:
        return b
    if b == ANY:
        return a
    if a.tag == "arr" and b.tag == "arr" and consistent(a, b):
        assert a.left and a.right and b.left and b.right
        return Arr(branch_type(a.left, b.left), branch_type(a.right, b.right))
    return ANY


# Elaborated expressions are tuples whose first item is the constructor tag.
IR = tuple[PyAny, ...]


def elaborate(expr: Expr, env: dict[str, Type] | None = None) -> tuple[Type, IR]:
    env = {} if env is None else env
    if isinstance(expr, Lit):
        typ = BOOL if isinstance(expr.value, bool) else INT
        return typ, ("lit", expr.value)
    if isinstance(expr, Var):
        if expr.name not in env:
            raise StaticError(f"unbound identifier {expr.name}")
        return env[expr.name], ("var", expr.name)
    if isinstance(expr, Fun):
        arg = expr.annotation or ANY
        body_type, body = elaborate(expr.body, {**env, expr.name: arg})
        return Arr(arg, body_type), ("fun", expr.name, body)
    if isinstance(expr, App):
        fn_type, fn = elaborate(expr.fn, env)
        arg_type, arg = elaborate(expr.arg, env)
        if fn_type.tag == "arr":
            assert fn_type.left and fn_type.right
            dom, rng = fn_type.left, fn_type.right
        else:
            dom, rng = ANY, ANY
            fn = ("cast", fn_type, Arr(ANY, ANY), fn)
        return rng, ("app", fn, ("cast", arg_type, dom, arg))
    if isinstance(expr, Bin):
        left_type, left = elaborate(expr.left, env)
        right_type, right = elaborate(expr.right, env)
        return INT, (
            "bin", expr.op,
            ("cast", left_type, INT, left),
            ("cast", right_type, INT, right),
        )
    if isinstance(expr, If):
        cond_type, cond = elaborate(expr.cond, env)
        yes_type, yes = elaborate(expr.then, env)
        no_type, no = elaborate(expr.otherwise, env)
        result = branch_type(yes_type, no_type)
        return result, (
            "if", ("cast", cond_type, BOOL, cond),
            ("cast", yes_type, result, yes),
            ("cast", no_type, result, no),
        )
    if isinstance(expr, Let):
        value_type, value = elaborate(expr.value, env)
        body_type, body = elaborate(expr.body, {**env, expr.name: value_type})
        return body_type, ("let", expr.name, value, body)
    if isinstance(expr, Ann):
        inner_type, inner = elaborate(expr.expr, env)
        return expr.typ, ("cast", inner_type, expr.typ, inner)
    raise AssertionError(expr)


def structurally_equal(
    original: Expr,
    migrated: Expr,
    binders: tuple[tuple[str, str], ...] = (),
) -> bool:
    while isinstance(migrated, Ann):
        migrated = migrated.expr
    if type(original) is not type(migrated):
        return False
    if isinstance(original, Lit):
        return original.value == migrated.value  # type: ignore[attr-defined]
    if isinstance(original, Var):
        assert isinstance(migrated, Var)
        original_depth = next(
            (i for i, (left, _) in enumerate(reversed(binders)) if left == original.name),
            None,
        )
        migrated_depth = next(
            (i for i, (_, right) in enumerate(reversed(binders)) if right == migrated.name),
            None,
        )
        if original_depth is None or migrated_depth is None:
            return original_depth is None and migrated_depth is None and original.name == migrated.name
        return original_depth == migrated_depth
    if isinstance(original, Fun):
        assert isinstance(migrated, Fun)
        return structurally_equal(
            original.body,
            migrated.body,
            binders + ((original.name, migrated.name),),
        )
    if isinstance(original, App):
        assert isinstance(migrated, App)
        return structurally_equal(original.fn, migrated.fn, binders) and structurally_equal(original.arg, migrated.arg, binders)
    if isinstance(original, Bin):
        assert isinstance(migrated, Bin)
        return original.op == migrated.op and structurally_equal(original.left, migrated.left, binders) and structurally_equal(original.right, migrated.right, binders)
    if isinstance(original, If):
        assert isinstance(migrated, If)
        return structurally_equal(original.cond, migrated.cond, binders) and structurally_equal(original.then, migrated.then, binders) and structurally_equal(original.otherwise, migrated.otherwise, binders)
    if isinstance(original, Let):
        assert isinstance(migrated, Let)
        return structurally_equal(original.value, migrated.value, binders) and structurally_equal(
            original.body,
            migrated.body,
            binders + ((original.name, migrated.name),),
        )
    if isinstance(original, Ann):
        return structurally_equal(original.expr, migrated, binders)
    raise AssertionError(original)


def all_lambdas_annotated(expr: Expr) -> bool:
    if isinstance(expr, (Lit, Var)):
        return True
    if isinstance(expr, Fun):
        return expr.annotation is not None and all_lambdas_annotated(expr.body)
    if isinstance(expr, App):
        return all_lambdas_annotated(expr.fn) and all_lambdas_annotated(expr.arg)
    if isinstance(expr, Bin):
        return all_lambdas_annotated(expr.left) and all_lambdas_annotated(expr.right)
    if isinstance(expr, If):
        return all_lambdas_annotated(expr.cond) and all_lambdas_annotated(expr.then) and all_lambdas_annotated(expr.otherwise)
    if isinstance(expr, Let):
        return all_lambdas_annotated(expr.value) and all_lambdas_annotated(expr.body)
    if isinstance(expr, Ann):
        return all_lambdas_annotated(expr.expr)
    raise AssertionError(expr)


def lambda_types(expr: Expr) -> list[Type]:
    if isinstance(expr, (Lit, Var)):
        return []
    if isinstance(expr, Fun):
        return [expr.annotation or ANY] + lambda_types(expr.body)
    if isinstance(expr, App):
        return lambda_types(expr.fn) + lambda_types(expr.arg)
    if isinstance(expr, Bin):
        return lambda_types(expr.left) + lambda_types(expr.right)
    if isinstance(expr, If):
        return lambda_types(expr.cond) + lambda_types(expr.then) + lambda_types(expr.otherwise)
    if isinstance(expr, Let):
        return lambda_types(expr.value) + lambda_types(expr.body)
    if isinstance(expr, Ann):
        return lambda_types(expr.expr)
    raise AssertionError(expr)


@dataclass
class Tagged:
    ground: str
    value: PyAny


@dataclass
class Closure:
    name: str
    body: IR
    env: dict[str, PyAny]

    def call(self, arg: PyAny, machine: "Machine") -> PyAny:
        machine.tick()
        return machine.eval(self.body, {**self.env, self.name: arg})


@dataclass
class Proxy:
    fn: Closure | "Proxy"
    source: Type
    target: Type

    def call(self, arg: PyAny, machine: "Machine") -> PyAny:
        machine.tick()
        assert self.source.left and self.source.right and self.target.left and self.target.right
        inner_arg = machine.cast(self.target.left, self.source.left, arg)
        result = self.fn.call(inner_arg, machine)
        return machine.cast(self.source.right, self.target.right, result)


def ground_type(typ: Type) -> str:
    return "fun" if typ.tag == "arr" else typ.tag


class Machine:
    def __init__(self, fuel: int = 50_000):
        self.fuel = fuel

    def tick(self) -> None:
        self.fuel -= 1
        if self.fuel < 0:
            raise Diverged("evaluation fuel exhausted")

    def cast(self, source: Type, target: Type, value: PyAny) -> PyAny:
        self.tick()
        if source == target:
            return value
        if source == ANY:
            if not isinstance(value, Tagged) or value.ground != ground_type(target):
                raise CastError(f"expected {ground_type(target)} tag")
            raw = value.value
            if target.tag == "arr":
                return self.cast(Arr(ANY, ANY), target, raw)
            return raw
        if target == ANY:
            if source.tag == "arr":
                value = self.cast(source, Arr(ANY, ANY), value)
            return Tagged(ground_type(source), value)
        if source.tag == "arr" and target.tag == "arr":
            if not isinstance(value, (Closure, Proxy)):
                raise CastError("function cast received a non-function")
            return Proxy(value, source, target)
        # Inconsistent base/shape casts are the doomed through-any case.
        return self.cast(ANY, target, self.cast(source, ANY, value))

    def eval(self, ir: IR, env: dict[str, PyAny] | None = None) -> PyAny:
        self.tick()
        env = {} if env is None else env
        tag = ir[0]
        if tag == "lit":
            return ir[1]
        if tag == "var":
            return env[ir[1]]
        if tag == "fun":
            return Closure(ir[1], ir[2], dict(env))
        if tag == "app":
            fn = self.eval(ir[1], env)
            arg = self.eval(ir[2], env)
            if not isinstance(fn, (Closure, Proxy)):
                raise CastError("application received a non-function")
            return fn.call(arg, self)
        if tag == "bin":
            left = self.eval(ir[2], env)
            right = self.eval(ir[3], env)
            if isinstance(left, bool) or isinstance(right, bool) or not isinstance(left, int) or not isinstance(right, int):
                raise CastError("arithmetic received a non-integer")
            return left + right if ir[1] == "+" else left * right
        if tag == "if":
            cond = self.eval(ir[1], env)
            if not isinstance(cond, bool):
                raise CastError("condition received a non-boolean")
            return self.eval(ir[2] if cond else ir[3], env)
        if tag == "let":
            value = self.eval(ir[2], env)
            return self.eval(ir[3], {**env, ir[1]: value})
        if tag == "cast":
            return self.cast(ir[1], ir[2], self.eval(ir[3], env))
        raise AssertionError(ir)


@dataclass(frozen=True)
class Outcome:
    kind: str
    value: int | bool | None = None


def run(expr: Expr, fuel: int = 50_000) -> Outcome:
    try:
        _, ir = elaborate(expr)
        value = Machine(fuel).eval(ir)
        if isinstance(value, (Closure, Proxy)):
            return Outcome("function")
        if isinstance(value, Tagged):
            # A closing context may itself return a value through `any`.
            value = value.value
            if isinstance(value, (Closure, Proxy)):
                return Outcome("function")
        if isinstance(value, bool):
            return Outcome("bool", value)
        if isinstance(value, int):
            return Outcome("int", value)
        raise AssertionError(value)
    except CastError:
        return Outcome("error")
    except Diverged:
        return Outcome("diverge")
    except RecursionError:
        # Python's call stack can be exhausted before the explicit fuel on a
        # tight self-application loop. This is the same observable outcome.
        return Outcome("diverge")


def at_any_boundary(expr: Expr) -> Expr:
    return Ann(expr, ANY)


def apply_args(expr: Expr, args: list[Expr]) -> Expr:
    result = at_any_boundary(expr)
    for arg in args:
        result = App(result, arg)
    return result


def info_nodes(typ: Type) -> int:
    if typ == ANY:
        return 0
    if typ.tag == "arr":
        assert typ.left and typ.right
        return 1 + info_nodes(typ.left) + info_nodes(typ.right)
    return 1


def matching_info(candidate: Type, target: Type) -> int:
    if target == ANY:
        return 0
    if target.tag == "arr":
        if candidate.tag != "arr":
            return 0
        assert candidate.left and candidate.right and target.left and target.right
        return 1 + matching_info(candidate.left, target.left) + matching_info(candidate.right, target.right)
    return 1 if candidate == target else 0


def precision_score(candidate: Expr, target: Expr) -> float:
    earned, possible = precision_points(candidate, target)
    return 1.0 if possible == 0 else min(1.0, earned / possible)


def precision_points(candidate: Expr, target: Expr) -> tuple[int, int]:
    candidate_types = lambda_types(candidate)
    target_types = lambda_types(target)
    if len(candidate_types) != len(target_types):
        return 0, sum(info_nodes(t) for t in target_types)
    possible = sum(info_nodes(t) for t in target_types)
    earned = sum(matching_info(c, t) for c, t in zip(candidate_types, target_types))
    return min(earned, possible), possible
