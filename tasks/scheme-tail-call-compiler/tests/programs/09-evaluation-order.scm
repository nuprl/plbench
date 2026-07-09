(define (mark text value)
  (begin (display text) value))

(display (+ (mark "a" 10) (mark "b" 20)))
(display "\n")
