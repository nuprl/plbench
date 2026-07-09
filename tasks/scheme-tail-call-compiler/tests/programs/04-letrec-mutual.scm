(display
  (letrec ((red? (lambda (n)
                   (if (= n 0) #t (blue? (- n 1)))))
           (blue? (lambda (n)
                    (if (= n 0) #f (red? (- n 1))))))
    (blue? 221)))
(display "\n")
