# Self-hosting ILVM compiler

`Language.md` specifies the ILVM language.

Install both of the following:

```
/app/ilvm            # executable ILVM implementation
/app/compiler.ilvm   # the compiler, written in ILVM
```

`/app/compiler.ilvm` compiles ILVM source to a native executable for this
machine and writes that executable to stdout.

## How we will test

### Fixed point

Compiling the compiler with itself must be a fixed point: the native binary
you get by compiling `/app/compiler.ilvm` must, when used to compile
`/app/compiler.ilvm` again, produce a **byte-identical** native binary.

```
/app/ilvm -m 4000000 -r 64 /app/compiler.ilvm -f /app/compiler.ilvm > /tmp/compiler1
# strip the trailing "Normal termination. Result = ..." line from /app/ilvm
chmod +x /tmp/compiler1

/tmp/compiler1 /app/compiler.ilvm > /tmp/compiler2
chmod +x /tmp/compiler2

cmp /tmp/compiler1 /tmp/compiler2
```

### Correctness

With that native compiler, compile and run guest programs. Example guest
`guest.ilvm`:

```
block 0 {
    exit(42);
}
```

```
/tmp/compiler1 guest.ilvm > /tmp/guest
chmod +x /tmp/guest
/tmp/guest
```

Expected:

```
Normal termination. Result = 42
```
