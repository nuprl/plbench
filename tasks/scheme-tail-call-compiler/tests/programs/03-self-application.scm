(define (walk self n total)
  (if (= n 0)
      total
      (self self (- n 1) (+ total 2))))

(display (walk walk 350 0))
(display "\n")
