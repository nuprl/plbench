;; bad: map is demanded with an integer where its recursive definition expects
;; a list, so the first car is a runtime type error.
(define (map-rec-bad f xs)
  (if (null? xs)
      '()
      (cons (f (car xs))
            (map-rec-bad f (cdr xs)))))

(map-rec-bad (lambda (n) (+ n 1)) 7)
