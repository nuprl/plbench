(display
  (letrec ((sum
             (lambda (xs)
               (if (null? xs)
                   0
                   (+ (car xs) (sum (cdr xs)))))))
    (sum '(1 2 3 4 5 6))))
