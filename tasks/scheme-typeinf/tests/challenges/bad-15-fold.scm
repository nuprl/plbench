;; bad: fold is demanded with a one-argument combiner, but its recursive
;; definition calls that combiner with two arguments.
(define (fold-rec-bad combine acc xs)
  (if (null? xs)
      acc
      (fold-rec-bad combine
                    (combine acc (car xs))
                    (cdr xs))))

(fold-rec-bad (lambda (x) x) 0 '(1 2 3))
