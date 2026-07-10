(define (check n)
  (letrec ((is-even (lambda (k) (if (= k 0) #t (is-odd (- k 1)))))
           (is-odd (lambda (k) (if (= k 0) #f (is-even (- k 1))))))
    (is-even n)))

(display (check 10))
