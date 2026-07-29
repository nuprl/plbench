(display
  (let ((x 10))
    (let ((add-x (lambda (y) (+ x y))))
      (let ((x 100))
        (add-x 7)))))
