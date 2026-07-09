Your task is to design a type inference algorithm for a small, Scheme-like
language.

## What Is Provided

The language is documented in `/app/Language.md`, there is a reference interpreter
in OCaml in `/app/minischeme-src`, and this interpreter is compiled and ready to
run at `/app/minischeme`.

You can run the interpreter in several ways. You can provide an expression
on the command-line:

```bash
/app/minischeme -e '(display (+ 1 2))'
```

You can load a file (or several files):

```bash
cat > program.scm <<EOF
(display "hello world\n")
EOF
/app/minischeme -l program.scm
```

You can also load files followed by an expression:

```bash
cat > lib.scm <<EOF
(define (fact n)
  (if (< n 2)
      1
      (* n (fact (- n 1)))))
EOF
/app/minischeme -l lib.scm -e '(display (fact 5))'
```

The interpreter does not print expression results automatically; use `display`
when you want output.

The interpreter checks special-form syntax and rejects unbound variables in the
combined program before evaluation. The combined program is all files loaded
with `-l`, followed by the optional `-e` expression.

We have also installed Python, OCaml, and Rust in this environment for you to use.

## What You Must Build

Your task is to design and implement a sound type inference algorithm for MiniScheme
that runs as follows:

```bash
/app/typeinf FILE.scm
```

The argument FILE.scm will be a MiniScheme program. Type inference may assume
that all top-level definitions are private and not updated from elsewhere,
with the exception of a `main` function. That is, if FILE.scm defines a function
called `main`, it must take exactly one argument and that argument may be an
arbitrary value. So, I will run the program as follows:


```bash
/app/minischeme -l FILE.scm -e '(main VALUE)'
```

Under these assumptions, typeinf must determine if MiniScheme may raise
a type when it runs FILE.scm and main is applied to an arbitrary value.
Typeinf must return exit code 0 if type errors are impossible and a non-zero
exit code if a type error may occur.

The challenge is that the type inference algorithm that you design and
implement must be flexible enough to support useful programs while still
maintaining soundness. I will test it with some examples that are obviously
well-typed, harder examples that involve heterogenous lists, and a metacircular
interpreter. I will also test it on programs that do raise type errors, and
admitting any program that raises a type error is unacceptable.
