;; ok: nested defines
(define (add1 x) (+ x 1))
(define (add2 x) (add1 (add1 x)))
(add2 40)
