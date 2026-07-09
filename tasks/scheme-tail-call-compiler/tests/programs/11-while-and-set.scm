(define (sum-below limit)
  (let ((index 0)
        (total 0))
    (begin
      (while (< index limit)
        (begin
          (set! total (+ total index))
          (set! index (+ index 1))))
      total)))

(display (sum-below 20))
(display "\n")
