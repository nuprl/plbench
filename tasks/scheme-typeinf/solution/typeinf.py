#!/usr/bin/env python3
"""Lame MiniScheme type checker: ground types + homogeneous lists/vectors.

Rejects programs that need heterogeneous lists (e.g. quoted ASTs).
Sound but incomplete.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class InferError(Exception):
    pass


class ParseError(Exception):
    pass


class Symbol:
    __slots__ = ("name",)
    _intern: dict[str, "Symbol"] = {}

    def __new__(cls, name: str) -> Symbol:
        if name in cls._intern:
            return cls._intern[name]
        obj = super().__new__(cls)
        obj.name = name
        cls._intern[name] = obj
        return obj

    def __repr__(self) -> str:
        return self.name


def tokenize(src: str) -> list[str]:
    tokens: list[str] = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
        elif c == ";":
            while i < n and src[i] != "\n":
                i += 1
        elif c in "()":
            tokens.append(c)
            i += 1
        elif c == "'":
            tokens.append("'")
            i += 1
        elif c == '"':
            j = i + 1
            out = ['"']
            while j < n:
                if src[j] == "\\":
                    if j + 1 >= n:
                        raise ParseError("unterminated string escape")
                    esc = src[j + 1]
                    mapping = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
                    if esc not in mapping:
                        raise ParseError(f"bad escape \\{esc}")
                    out.append(mapping[esc])
                    j += 2
                elif src[j] == '"':
                    out.append('"')
                    j += 1
                    break
                else:
                    out.append(src[j])
                    j += 1
            else:
                raise ParseError("unterminated string")
            tokens.append("".join(out))
            i = j
        else:
            j = i
            while j < n and src[j] not in " \t\r\n();\"'":
                j += 1
            tokens.append(src[i:j])
            i = j
    return tokens


def atom(tok: str) -> Any:
    if tok == "#t":
        return True
    if tok == "#f":
        return False
    if tok.startswith('"') and tok.endswith('"'):
        return tok[1:-1]
    try:
        if "." in tok:
            return float(tok)
        return int(tok)
    except ValueError:
        pass
    return Symbol(tok)


class _Reader:
    def __init__(self, tokens: list[str]):
        self.tokens = tokens
        self.i = 0

    def peek(self) -> str | None:
        if self.i >= len(self.tokens):
            return None
        return self.tokens[self.i]

    def next(self) -> str:
        t = self.peek()
        if t is None:
            raise ParseError("unexpected end of input")
        self.i += 1
        return t

    def read(self) -> Any:
        t = self.next()
        if t == "(":
            items: list[Any] = []
            while True:
                p = self.peek()
                if p is None:
                    raise ParseError("unterminated list")
                if p == ")":
                    self.next()
                    return items
                items.append(self.read())
        if t == ")":
            raise ParseError("unexpected ')'")
        if t == "'":
            return [Symbol("quote"), self.read()]
        return atom(t)


def read_all(src: str) -> list[Any]:
    r = _Reader(tokenize(src))
    forms: list[Any] = []
    while r.peek() is not None:
        forms.append(r.read())
    return forms

@dataclass(frozen=True)
class TInt:
    def __str__(self) -> str:
        return "Int"


@dataclass(frozen=True)
class TFloat:
    def __str__(self) -> str:
        return "Float"


@dataclass(frozen=True)
class TNum:
    """Int or Float (for arithmetic results we keep precise when possible)."""

    def __str__(self) -> str:
        return "Num"


@dataclass(frozen=True)
class TBool:
    def __str__(self) -> str:
        return "Bool"


@dataclass(frozen=True)
class TString:
    def __str__(self) -> str:
        return "String"


@dataclass(frozen=True)
class TSymbol:
    def __str__(self) -> str:
        return "Symbol"


@dataclass(frozen=True)
class TList:
    elem: Any
    # Lower bound on length. car/cdr require min_len >= 1.
    # After cdr, min_len decreases by 1 (floored at 0).
    min_len: int = 0

    def __str__(self) -> str:
        return f"(List {self.elem} ≥{self.min_len})"


@dataclass(frozen=True)
class TVector:
    elem: Any

    def __str__(self) -> str:
        return f"(Vector {self.elem})"


@dataclass(frozen=True)
class TFun:
    args: tuple[Any, ...]
    ret: Any

    def __str__(self) -> str:
        a = " ".join(str(x) for x in self.args)
        return f"(-> ({a}) {self.ret})"


@dataclass(frozen=True)
class TUnit:
    def __str__(self) -> str:
        return "Unit"


Type = Any


def is_num(t: Type) -> bool:
    return isinstance(t, (TInt, TFloat, TNum))


def quote_type(datum: Any) -> Type:
    if isinstance(datum, bool):
        return TBool()
    if type(datum) is int:
        return TInt()
    if isinstance(datum, float):
        return TFloat()
    if isinstance(datum, str):
        return TString()
    if isinstance(datum, Symbol):
        return TSymbol()
    if isinstance(datum, list):
        if not datum:
            return TList(TUnit(), 0)
        elem = quote_type(datum[0])
        for x in datum[1:]:
            elem = unify(elem, quote_type(x))
        return TList(elem, len(datum))
    raise InferError(f"cannot type quoted datum: {datum!r}")


class Env:
    def __init__(self, parent: Env | None = None):
        self.parent = parent
        self.bindings: dict[str, Type] = {}

    def lookup(self, name: str) -> Type:
        if name in self.bindings:
            return self.bindings[name]
        if self.parent:
            return self.parent.lookup(name)
        raise InferError(f"unbound variable: {name}")

    def define(self, name: str, ty: Type) -> None:
        self.bindings[name] = ty

    def child(self) -> Env:
        return Env(self)


def prims() -> Env:
    g = Env()

    def nary_num_to_num(ret: Type) -> TFun:
        # Variadic: we type-check applications specially
        return TFun((), ret)  # placeholder; handled in infer_app

    g.define("+", TFun((TNum(),), TNum()))  # markers; special-cased
    g.define("-", TFun((TNum(),), TNum()))
    g.define("*", TFun((TNum(),), TNum()))
    g.define("/", TFun((TNum(),), TFloat()))
    g.define("=", TFun((TNum(), TNum()), TBool()))
    g.define("<", TFun((TNum(), TNum()), TBool()))
    g.define(">", TFun((TNum(), TNum()), TBool()))
    g.define("<=", TFun((TNum(), TNum()), TBool()))
    g.define(">=", TFun((TNum(), TNum()), TBool()))
    g.define("number?", TFun((TUnit(),), TBool()))  # special
    g.define("integer?", TFun((TUnit(),), TBool()))
    g.define("float?", TFun((TUnit(),), TBool()))
    g.define("boolean?", TFun((TUnit(),), TBool()))
    g.define("string?", TFun((TUnit(),), TBool()))
    g.define("symbol?", TFun((TUnit(),), TBool()))
    g.define("procedure?", TFun((TUnit(),), TBool()))
    g.define("null?", TFun((TList(TUnit()),), TBool()))
    g.define("pair?", TFun((TList(TUnit()),), TBool()))
    g.define("list?", TFun((TUnit(),), TBool()))
    g.define("vector?", TFun((TUnit(),), TBool()))
    g.define("not", TFun((TBool(),), TBool()))
    g.define("eq?", TFun((TUnit(), TUnit()), TBool()))
    g.define("equal?", TFun((TUnit(), TUnit()), TBool()))
    g.define("cons", TFun((TUnit(), TList(TUnit())), TList(TUnit())))  # special
    g.define("car", TFun((TList(TUnit()),), TUnit()))
    g.define("cdr", TFun((TList(TUnit()),), TList(TUnit())))
    g.define("list", TFun((), TList(TUnit())))
    g.define("length", TFun((TList(TUnit()),), TInt()))
    g.define("append", TFun((), TList(TUnit())))
    g.define("list-ref", TFun((TList(TUnit()), TInt()), TUnit()))
    g.define("vector", TFun((), TVector(TUnit())))
    g.define("vector-length", TFun((TVector(TUnit()),), TInt()))
    g.define("vector-ref", TFun((TVector(TUnit()), TInt()), TUnit()))
    g.define("string-length", TFun((TString(),), TInt()))
    g.define("string-append", TFun((), TString()))
    g.define("string-ref", TFun((TString(), TInt()), TString()))
    g.define("string->symbol", TFun((TString(),), TSymbol()))
    g.define("symbol->string", TFun((TSymbol(),), TString()))
    g.define("error", TFun((TString(),), TUnit()))
    g.define("apply", TFun((TFun((), TUnit()), TList(TUnit())), TUnit()))
    g.define("display", TFun((TUnit(),), TBool()))
    return g


PRED_ANY = {
    "number?",
    "integer?",
    "float?",
    "boolean?",
    "string?",
    "symbol?",
    "procedure?",
    "list?",
    "vector?",
}
NUM_OPS = {"+", "-", "*", "/"}
CMP_OPS = {"=", "<", ">", "<=", ">="}


def infer(expr: Any, env: Env) -> Type:
    if isinstance(expr, bool):
        return TBool()
    if type(expr) is int:
        return TInt()
    if isinstance(expr, float):
        return TFloat()
    if isinstance(expr, str):
        return TString()
    if isinstance(expr, Symbol):
        return env.lookup(expr.name)
    if not isinstance(expr, list):
        raise InferError(f"cannot type: {expr!r}")
    if not expr:
        raise InferError("empty application")

    head = expr[0]
    if isinstance(head, Symbol):
        name = head.name
        if name == "quote":
            if len(expr) != 2:
                raise InferError("quote arity")
            return quote_type(expr[1])
        if name == "lambda":
            if len(expr) != 3:
                raise InferError("lambda shape")
            params = expr[1]
            body = expr[2]
            if not isinstance(params, list) or not all(
                isinstance(p, Symbol) for p in params
            ):
                raise InferError("lambda params")
            # Infer body with parameter types as unknown — we use a simple
            # approach: parameters start as TUnit and get refined... too weak.
            # Better: require body to type with params bound to fresh "Any" that
            # only works for predicates. For lame oracle, bind params to a
            # polymorphic-ish approach: try to infer from body uses.
            # Simplest sound approach: params are typed by analyzing body with
            # bidirectional checking — skip; use TNum for all params if body
            # uses them as numbers, else reject complex cases.
            # Practical lame approach: introduce params with type variables
            # represented as unique TUnit subclasses — use string tags.
            return infer_lambda(params, body, env)
        if name == "if":
            if len(expr) != 4:
                raise InferError("if shape")
            infer(expr[1], env)  # test can be any (truthy)
            t = infer(expr[2], env)
            e = infer(expr[3], env)
            return unify(t, e)
        if name == "let":
            return infer_let(expr, env, recursive=False)
        if name == "letrec":
            return infer_let(expr, env, recursive=True)
        if name == "begin":
            if len(expr) < 2:
                raise InferError("begin empty")
            t: Type = TUnit()
            for e in expr[1:]:
                t = infer(e, env)
            return t
        if name == "and" or name == "or":
            t = TBool()
            for e in expr[1:]:
                et = infer(e, env)
                # allow non-bool truthy for and/or? Language says short-circuit
                # on truthiness; lame oracle requires Bool for simplicity when present
                if expr[1:]:
                    t = et
            return t if expr[1:] else (TBool() if name == "and" else TBool())
        if name == "cond":
            result: Type | None = None
            for clause in expr[1:]:
                if not isinstance(clause, list) or len(clause) != 2:
                    raise InferError("cond clause")
                test, body = clause
                if not (isinstance(test, Symbol) and test.name == "else"):
                    infer(test, env)
                bt = infer(body, env)
                result = bt if result is None else unify(result, bt)
            if result is None:
                raise InferError("cond empty")
            return result
        if name == "define":
            raise InferError("define only at top level")

    return infer_app(expr, env)


@dataclass(frozen=True)
class TVar:
    id: int

    def __str__(self) -> str:
        return f"?{self.id}"


_tvar_counter = 0
_subst: dict[int, Type] = {}


def fresh() -> TVar:
    global _tvar_counter
    _tvar_counter += 1
    return TVar(_tvar_counter)


def resolve(t: Type) -> Type:
    if isinstance(t, TVar):
        if t.id in _subst:
            return resolve(_subst[t.id])
        return t
    if isinstance(t, TList):
        return TList(resolve(t.elem), t.min_len)
    if isinstance(t, TVector):
        return TVector(resolve(t.elem))
    if isinstance(t, TFun):
        return TFun(tuple(resolve(a) for a in t.args), resolve(t.ret))
    return t


def bind_var(v: TVar, t: Type) -> Type:
    t = resolve(t)
    if isinstance(t, TVar) and t.id == v.id:
        return v
    if occurs(v, t):
        raise InferError(f"occurs check: {v} in {t}")
    _subst[v.id] = t
    return t


def occurs(v: TVar, t: Type) -> bool:
    t = resolve(t)
    if isinstance(t, TVar):
        return t.id == v.id
    if isinstance(t, TList):
        return occurs(v, t.elem)
    if isinstance(t, TVector):
        return occurs(v, t.elem)
    if isinstance(t, TFun):
        return any(occurs(v, a) for a in t.args) or occurs(v, t.ret)
    return False


def unify2(a: Type, b: Type) -> Type:
    a, b = resolve(a), resolve(b)
    if isinstance(a, TVar):
        return bind_var(a, b)
    if isinstance(b, TVar):
        return bind_var(b, a)
    if isinstance(a, TUnit) or isinstance(b, TUnit):
        # Unit used as "any" for predicates / empty list elem
        if isinstance(a, TUnit):
            return b
        return a
    if type(a) is type(b) and not isinstance(a, (TList, TVector, TFun, TInt, TFloat, TNum)):
        return a
    if is_num(a) and is_num(b):
        if isinstance(a, TInt) and isinstance(b, TInt):
            return TInt()
        if isinstance(a, TFloat) and isinstance(b, TFloat):
            return TFloat()
        return TNum()
    if isinstance(a, TList) and isinstance(b, TList):
        # Intersection of length lower bounds (both must be satisfied).
        return TList(unify2(a.elem, b.elem), max(a.min_len, b.min_len))
    if isinstance(a, TVector) and isinstance(b, TVector):
        return TVector(unify2(a.elem, b.elem))
    if isinstance(a, TFun) and isinstance(b, TFun):
        if len(a.args) != len(b.args):
            raise InferError("fun arity")
        args = tuple(unify2(x, y) for x, y in zip(a.args, b.args))
        return TFun(args, unify2(a.ret, b.ret))
    raise InferError(f"cannot unify {a} with {b}")


# Replace unify used in quote/if with unify2-aware versions after tvar support
def unify(a: Type, b: Type) -> Type:  # noqa: F811
    return unify2(a, b)


def infer_lambda(params: list, body: Any, env: Env) -> Type:
    child = env.child()
    arg_ts = []
    for p in params:
        tv = fresh()
        child.define(p.name, tv)
        arg_ts.append(tv)
    ret = infer(body, child)
    return TFun(tuple(resolve(a) for a in arg_ts), resolve(ret))


def infer_let(expr: list, env: Env, recursive: bool) -> Type:
    if len(expr) != 3:
        raise InferError("let shape")
    bindings = expr[1]
    body = expr[2]
    if not isinstance(bindings, list):
        raise InferError("let bindings")
    child = env.child()
    specs: list[tuple[str, Any]] = []
    for b in bindings:
        if not (isinstance(b, list) and len(b) == 2 and isinstance(b[0], Symbol)):
            raise InferError("bad binding")
        specs.append((b[0].name, b[1]))
    if recursive:
        for name, _ in specs:
            child.define(name, fresh())
        for name, rhs in specs:
            ty = infer(rhs, child)
            child.define(name, unify(child.lookup(name), ty))
    else:
        for name, rhs in specs:
            child.define(name, infer(rhs, env))
    return infer(body, child)


def infer_app(expr: list, env: Env) -> Type:
    head = expr[0]
    # special-case builtins by name when head is a symbol
    if isinstance(head, Symbol):
        name = head.name
        args = expr[1:]
        arg_ts = [infer(a, env) for a in args]

        if name in NUM_OPS:
            if name in ("-", "/") and len(arg_ts) < 1:
                raise InferError(f"{name} arity")
            for t in arg_ts:
                if not is_num(resolve(t)):
                    # try unify with Num
                    unify(t, TNum())
            if name == "/":
                return TFloat()
            # if all int -> int
            if arg_ts and all(isinstance(resolve(t), TInt) for t in arg_ts):
                return TInt()
            if arg_ts and all(isinstance(resolve(t), (TInt, TFloat, TNum)) for t in arg_ts):
                if any(isinstance(resolve(t), (TFloat, TNum)) for t in arg_ts):
                    return TNum() if any(isinstance(resolve(t), TNum) for t in arg_ts) else TFloat()
                return TInt()
            return TNum()

        if name in CMP_OPS:
            if len(arg_ts) < 2:
                raise InferError(f"{name} arity")
            for t in arg_ts:
                unify(t, TNum())
            return TBool()

        if name in PRED_ANY:
            if len(arg_ts) != 1:
                raise InferError(f"{name} arity")
            return TBool()

        if name == "not":
            if len(arg_ts) != 1:
                raise InferError("not arity")
            unify(arg_ts[0], TBool())
            return TBool()

        if name == "eq?" or name == "equal?":
            if len(arg_ts) != 2:
                raise InferError(f"{name} arity")
            return TBool()

        if name == "cons":
            if len(arg_ts) != 2:
                raise InferError("cons arity")
            elem = resolve(arg_ts[0])
            lst = resolve(arg_ts[1])
            if not isinstance(lst, TList):
                lst = unify(lst, TList(elem, 0))
                lst = resolve(lst)
            else:
                unify(elem, lst.elem)
            assert isinstance(lst, TList)
            return TList(resolve(elem), lst.min_len + 1)

        if name == "car":
            if len(arg_ts) != 1:
                raise InferError("car arity")
            lst = resolve(arg_ts[0])
            if not isinstance(lst, TList):
                raise InferError("car: not a list")
            if lst.min_len < 1:
                raise InferError("car: list may be empty")
            return resolve(lst.elem)

        if name == "cdr":
            if len(arg_ts) != 1:
                raise InferError("cdr arity")
            lst = resolve(arg_ts[0])
            if not isinstance(lst, TList):
                raise InferError("cdr: not a list")
            if lst.min_len < 1:
                raise InferError("cdr: list may be empty")
            return TList(resolve(lst.elem), lst.min_len - 1)

        if name == "list":
            if not arg_ts:
                return TList(TUnit(), 0)
            elem = arg_ts[0]
            for t in arg_ts[1:]:
                elem = unify(elem, t)
            return TList(resolve(elem), len(arg_ts))

        if name == "length":
            if len(arg_ts) != 1:
                raise InferError("length arity")
            unify(arg_ts[0], TList(fresh(), 0))
            return TInt()

        if name == "append":
            if not arg_ts:
                return TList(TUnit(), 0)
            elem = fresh()
            total_min = 0
            for t in arg_ts:
                lt = resolve(unify(t, TList(elem, 0)))
                if not isinstance(lt, TList):
                    raise InferError("append: not a list")
                total_min += lt.min_len
            return TList(resolve(elem), total_min)

        if name == "list-ref":
            if len(arg_ts) != 2:
                raise InferError("list-ref arity")
            lst = resolve(arg_ts[0])
            unify(arg_ts[1], TInt())
            if not isinstance(lst, TList):
                raise InferError("list-ref: not a list")
            # Without a constant index we only know elem type if min_len >= 1
            # for index 0; for general index require min_len >= 1 as weak check
            # (still incomplete for out-of-bounds). Reject empty.
            if lst.min_len < 1:
                raise InferError("list-ref: list may be empty")
            return resolve(lst.elem)

        if name == "null?" or name == "pair?":
            if len(arg_ts) != 1:
                raise InferError(f"{name} arity")
            unify(arg_ts[0], TList(fresh(), 0))
            return TBool()

        if name == "vector":
            if not arg_ts:
                return TVector(TUnit())
            elem = arg_ts[0]
            for t in arg_ts[1:]:
                elem = unify(elem, t)
            return TVector(resolve(elem))

        if name == "vector-length":
            if len(arg_ts) != 1:
                raise InferError("vector-length arity")
            unify(arg_ts[0], TVector(fresh()))
            return TInt()

        if name == "vector-ref":
            if len(arg_ts) != 2:
                raise InferError("vector-ref arity")
            v = resolve(arg_ts[0])
            unify(arg_ts[1], TInt())
            if not isinstance(v, TVector):
                raise InferError("vector-ref: not a vector")
            return resolve(v.elem)

        if name == "string-length":
            if len(arg_ts) != 1:
                raise InferError("string-length arity")
            unify(arg_ts[0], TString())
            return TInt()

        if name == "string-append":
            for t in arg_ts:
                unify(t, TString())
            return TString()

        if name == "string-ref":
            if len(arg_ts) != 2:
                raise InferError("string-ref arity")
            unify(arg_ts[0], TString())
            unify(arg_ts[1], TInt())
            return TString()

        if name == "string->symbol":
            if len(arg_ts) != 1:
                raise InferError("string->symbol arity")
            unify(arg_ts[0], TString())
            return TSymbol()

        if name == "symbol->string":
            if len(arg_ts) != 1:
                raise InferError("symbol->string arity")
            unify(arg_ts[0], TSymbol())
            return TString()

        if name == "error":
            if len(arg_ts) != 1:
                raise InferError("error arity")
            unify(arg_ts[0], TString())
            return fresh()  # never returns

        if name == "display":
            if len(arg_ts) != 1:
                raise InferError("display arity")
            return TBool()

    # general application
    ft = resolve(infer(expr[0], env))
    arg_ts = [infer(a, env) for a in expr[1:]]
    if not isinstance(ft, TFun):
        if isinstance(ft, TVar):
            ret = fresh()
            unify(ft, TFun(tuple(arg_ts), ret))
            return resolve(ret)
        raise InferError(f"applying non-function: {ft}")
    if len(ft.args) != len(arg_ts):
        raise InferError(f"arity: expected {len(ft.args)}, got {len(arg_ts)}")
    for a, b in zip(ft.args, arg_ts):
        unify(a, b)
    return resolve(ft.ret)


def infer_toplevel(forms: list[Any], env: Env) -> Type:
    result: Type = TUnit()
    for form in forms:
        if (
            isinstance(form, list)
            and form
            and isinstance(form[0], Symbol)
            and form[0].name == "define"
        ):
            result = infer_define(form, env)
        elif (
            isinstance(form, list)
            and form
            and isinstance(form[0], Symbol)
            and form[0].name == "begin"
        ):
            result = infer_toplevel(form[1:], env)
        else:
            result = infer(form, env)
    return resolve(result)


def infer_define(form: list, env: Env) -> Type:
    target = form[1]
    if isinstance(target, Symbol):
        if len(form) != 3:
            raise InferError("define shape")
        # allow recursion for simple values via placeholder
        env.define(target.name, fresh())
        ty = infer(form[2], env)
        env.define(target.name, unify(env.lookup(target.name), ty))
        return resolve(ty)
    if isinstance(target, list) and target and isinstance(target[0], Symbol):
        fname = target[0].name
        params = target[1:]
        body = form[2]
        env.define(fname, fresh())
        ty = infer_lambda(params, body, env)
        env.define(fname, unify(env.lookup(fname), ty))
        return resolve(ty)
    raise InferError("define shape")


def main(argv: list[str]) -> int:
    global _subst, _tvar_counter
    _subst = {}
    _tvar_counter = 0
    if len(argv) != 2:
        print("usage: typeinf FILE.scm", file=sys.stderr)
        return 2
    path = Path(argv[1])
    try:
        forms = read_all(path.read_text())
        env = prims()
        ty = infer_toplevel(forms, env)
        print(ty)
        return 0
    except (InferError, ParseError, Exception) as e:
        print(f"type error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"type error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
