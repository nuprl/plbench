;; bad: the demanded recursive branch multiplies its accumulator by a string.
(define (fact-tail-bad n acc)
  (if (< n 2)
      acc
      (fact-tail-bad (- n 1) (* acc "not-a-number"))))

(fact-tail-bad 5 1)
