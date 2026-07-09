(define (classify n)
  (if (< n 0)
      "negative"
      (if (= n 0)
          "zero"
          "positive")))

(display (classify -5))
(display " ")
(display (classify 0))
(display " ")
(display (classify 5))
(display "\n")
