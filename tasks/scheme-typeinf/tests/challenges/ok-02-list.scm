;; ok: let + homogeneous list
(let ((xs (list 1 2 3)))
  (+ (car xs) (car (cdr xs))))
