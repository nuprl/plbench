;; hard-ok: nested quoted program with if
(let ((prog (quote (if #t 10 20))))
  (if (eq? (car prog) 'if)
      (if (car (cdr prog))
          (car (cdr (cdr prog)))
          (car (cdr (cdr (cdr prog)))))
      0))
