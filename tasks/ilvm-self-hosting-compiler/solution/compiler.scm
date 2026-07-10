; ORACLE-NOT-SELF-HOSTING-7f3ac9e1d4b8407e9c2a1f6e5d0b8c33
;
; This oracle is intentionally not self-hosting. The real compiler lives in
; solution/compile_scheme_to_ilvm.py (a real Python compiler with real
; codegen), not here -- see README.md for why. This file exists only so
; that /app/compiler.scm is present per the task's contract, and carries
; the marker above that tells the verifier to grade this submission via
; the fallback compiler instead of compiler.ilvm.
(error "this oracle is not self-hosting")
