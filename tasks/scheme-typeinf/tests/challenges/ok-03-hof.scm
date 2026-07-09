;; ok: higher-order function, homogeneous
(let ((apply-twice
       (lambda (f x)
         (f (f x)))))
  (apply-twice (lambda (n) (+ n 1)) 10))
