;; ok: recursive higher-order map over any guarded list. Both the concrete call
;; and the arbitrary main argument demand the recursive definition.
(define (map-rec f xs)
  (if (null? xs)
      '()
      (cons (f (car xs))
            (map-rec f (cdr xs)))))

(define (main xs)
  (if (list? xs)
      (map-rec (lambda (x) x) xs)
      '()))

(main '(1 two "three"))
