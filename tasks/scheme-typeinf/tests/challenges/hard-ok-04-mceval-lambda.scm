;; hard-ok: metacircular eval of a lambda application
(ms-eval (quote ((lambda (x) (+ x 1)) 41)) (ms-initial-env))
