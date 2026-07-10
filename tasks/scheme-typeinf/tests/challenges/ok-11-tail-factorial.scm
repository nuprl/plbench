;; ok: tail-recursive factorial over any guarded numeric input. Both the
;; concrete call and the arbitrary main argument demand the recursive definition.
(define (fact-tail n acc)
  (if (< n 2)
      acc
      (fact-tail (- n 1) (* acc n))))

(define (main n)
  (if (number? n)
      (fact-tail n 1)
      1))

(main 5)
