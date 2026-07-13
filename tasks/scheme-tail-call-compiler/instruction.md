Your task is to write a source-to-source compiler that restores proper tail
calls for a small, Scheme-like language.

## What Is Provided

The MiniScheme language is documented in `/app/Language.md`, there is a
reference interpreter in OCaml in `/app/minischeme-src`, and this interpreter
is compiled and ready to run at `/app/minischeme`.

You can provide an expression on the command line:

```bash
/app/minischeme -e '(display (+ 1 2))'
```

You can load one or more files:

```bash
/app/minischeme -l program.scm
```

The reference interpreter normally implements proper tail calls. It also has
an optional stack-depth limit:

```bash
/app/minischeme --max-stack-depth 10 -l program.scm
```

When `--max-stack-depth N` is present, nested evaluation, including calls in
tail position, is limited to depth `N`. Evaluation fails if it exceeds the
limit. If the option is omitted, stack-depth counting is disabled and proper
tail calls are retained. The exact language and interpreter behavior are
specified in `/app/Language.md`.

Python, OCaml, and Rust are installed in the environment. You may implement
your compiler in any language.

## What You Must Build

Write an executable MiniScheme-to-MiniScheme compiler that implements proper
tail calls. It must have exactly this CLI:

```bash
/app/compiler INPUT.scm OUTPUT.scm
```

Your compiler must write a complete MiniScheme program to `OUTPUT.scm` and exit
with status 0. If compilation fails, it must exit nonzero. The output program
must have the same observable behavior as the input program: the same bytes on
standard output, the same evaluation order and effects, and the same successful
result or runtime failure.

We will run the output with a stack limit of 10:

```bash
/app/compiler INPUT.scm OUTPUT.scm
/app/minischeme --max-stack-depth 10 -l OUTPUT.scm
```

The output program should work even if the input would have blown the stack with
that limit.
