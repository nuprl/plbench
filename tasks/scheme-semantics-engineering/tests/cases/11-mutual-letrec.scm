(display
  (letrec
    ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1)))))
     (odd? (lambda (n) (if (= n 0) #f (even? (- n 1))))))
    (list (even? 12) (odd? 9))))
