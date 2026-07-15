;; bad: the second eq? operand is a variable, not quoted symbol data.  The
;; selected branch therefore receives #t and passes it to symbol->string.
(define comparison-value #t)

(let ((x #t))
  (if (eq? x comparison-value)
      (symbol->string x)
      "ok"))
