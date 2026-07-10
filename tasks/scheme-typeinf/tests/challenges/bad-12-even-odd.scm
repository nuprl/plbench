;; bad: the demanded odd branch adds a number to the Boolean returned by even.
(define (even-rec-bad? n)
  (if (= n 0)
      #t
      (not (odd-rec-bad? (- n 1)))))

(define (odd-rec-bad? n)
  (if (= n 0)
      #f
      (+ 1 (even-rec-bad? (- n 1)))))

(even-rec-bad? 2)
