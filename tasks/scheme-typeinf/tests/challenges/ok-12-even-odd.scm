;; ok: mutually recursive, non-tail even?/odd? over any guarded numeric input.
;; Both the concrete call and the arbitrary main argument demand both definitions.
(define (even-rec? n)
  (if (= n 0)
      #t
      (not (odd-rec? (- n 1)))))

(define (odd-rec? n)
  (if (= n 0)
      #f
      (not (even-rec? (- n 1)))))

(define (main n)
  (if (number? n)
      (even-rec? n)
      #f))

(main 6)
