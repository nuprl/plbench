# nuprl/ilvm-interpreter

Implement an ILVM interpreter at `/app/ilvm` from `Language.md`. Verification
uses the behavioral suite from `arjunguha/ilvm` (`src/main.rs` unit tests).

## Running

```
/app/ilvm -m 500 -r 10 program.ilvm
/app/ilvm -m 500 -r 10 program.ilvm -l arg0 -f argfile.txt
```
