;; hard-ok: drive the agent's metacircular interpreter on (+ 1 2)
;; Requires /app/mceval.scm to be loadable; this file is checked with:
;;   /app/minischeme -l /app/mceval.scm this-file
;; The verifier loads mceval before running hard-ok files that need it.
(ms-eval (quote (+ 1 2)) (ms-initial-env))
