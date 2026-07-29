(display
  (letrec
    ((map (lambda (f xs)
            (if (null? xs)
                '()
                (cons (f (car xs)) (map f (cdr xs)))))))
    (map (lambda (x) (* x x)) '(1 2 3 4 5))))
