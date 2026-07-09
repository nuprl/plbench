(define (left n)
  (if (= n 0) "left" (dispatch #f (- n 1))))

(define (right n)
  (if (= n 0) "right" (dispatch #t (- n 1))))

(define (dispatch use-left n)
  ((if use-left left right) n))

(display (dispatch #t 175))
(display "\n")
