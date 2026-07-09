(define (even? n)
  (if (= n 0)
      #t
      (odd? (- n 1))))

(define (odd? n)
  (if (= n 0)
      #f
      (even? (- n 1))))

(display (even? 100))
(display " ")
(display (odd? 101))
(display "\n")
