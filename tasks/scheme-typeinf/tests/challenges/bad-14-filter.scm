;; bad: filter is demanded with a non-procedure predicate, which is applied by
;; the recursive definition.
(define (filter-rec-bad pred xs)
  (if (null? xs)
      '()
      (if (pred (car xs))
          (cons (car xs) (filter-rec-bad pred (cdr xs)))
          (filter-rec-bad pred (cdr xs)))))

(filter-rec-bad 0 '(1 2 3))
