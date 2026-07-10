;; ok: recursive higher-order filter over any guarded list. Both the concrete
;; call and the arbitrary main argument demand the recursive definition.
(define (filter-rec pred xs)
  (if (null? xs)
      '()
      (if (pred (car xs))
          (cons (car xs) (filter-rec pred (cdr xs)))
          (filter-rec pred (cdr xs)))))

(define (main xs)
  (if (list? xs)
      (filter-rec number? xs)
      '()))

(main '(1 no 2 "no"))
