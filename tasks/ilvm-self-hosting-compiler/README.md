# nuprl/ilvm-self-hosting-compiler

Build `/app/ilvm` and a self-hosting native-code ILVM compiler at
`/app/compiler.ilvm` from `Language.md`.

## Expected layout

| Path | Role |
|------|------|
| `/app/ilvm` | Executable ILVM implementation |
| `/app/compiler.ilvm` | Compiler (ILVM source); writes a native executable to stdout |

## Fixed point

```
/app/ilvm -m 4000000 -r 64 /app/compiler.ilvm -f /app/compiler.ilvm > /tmp/compiler1
# strip trailing "Normal termination. Result = ..." from /app/ilvm
chmod +x /tmp/compiler1

/tmp/compiler1 /app/compiler.ilvm > /tmp/compiler2
cmp /tmp/compiler1 /tmp/compiler2
```

## Compile and run a guest

```
/tmp/compiler1 guest.ilvm > /tmp/guest
chmod +x /tmp/guest
/tmp/guest
```

## Lameness check

Harbor does not tell the verifier which agent ran. Real solutions must emit ELF
binaries. The bundled oracle cheats with shell wrappers and embeds the marker
`ILVM_ORACLE_LAME_COMPILER` so the verifier can skip the ELF requirement for
that oracle only.
