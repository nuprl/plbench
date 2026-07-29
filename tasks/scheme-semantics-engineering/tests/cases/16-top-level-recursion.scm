(define (length-tail xs acc)
  (if (null? xs)
      acc
      (length-tail (cdr xs) (+ acc 1))))
(display (length-tail '(a b c d e f g h) 0))
