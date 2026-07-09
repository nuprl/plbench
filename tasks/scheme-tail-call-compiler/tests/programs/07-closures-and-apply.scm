(define (make-adder amount)
  (lambda (value) (+ amount value)))

(let ((add-seven (make-adder 7)))
  (begin
    (display (add-seven 35))
    (display " ")
    (display (apply add-seven (list 5)))
    (display "\n")))
