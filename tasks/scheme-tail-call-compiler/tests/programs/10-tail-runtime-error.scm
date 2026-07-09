(define (descend n)
  (if (= n 0)
      (error "bottom")
      (descend (- n 1))))

(descend 125)
