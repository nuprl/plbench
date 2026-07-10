(define (classify n)
  (if (< n 0)
      "negative"
      (if (= n 0)
          "zero"
          "positive")))

(display (classify -5))
(display (classify 0))
(display (classify 5))
