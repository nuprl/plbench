(define (countdown n acc)
  (if (= n 0)
      acc
      (countdown (- n 1) (+ acc 1))))

(display (countdown 600 0))
(display "\n")
