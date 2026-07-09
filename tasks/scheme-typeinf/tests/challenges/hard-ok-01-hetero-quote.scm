;; hard-ok: heterogeneous quoted AST inspected with car/cdr/eq?
(let ((prog (quote (+ 1 2))))
  (if (eq? (car prog) '+)
      (+ (car (cdr prog)) (car (cdr (cdr prog))))
      0))
