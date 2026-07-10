;; ok: recursive higher-order left fold over any guarded list. Both the concrete
;; call and the arbitrary main argument demand the recursive definition.
(define (fold-rec combine acc xs)
  (if (null? xs)
      acc
      (fold-rec combine
                (combine acc (car xs))
                (cdr xs))))

(define (main xs)
  (if (list? xs)
      (fold-rec (lambda (acc x) (cons x acc)) '() xs)
      '()))

(main '(1 two "three"))
