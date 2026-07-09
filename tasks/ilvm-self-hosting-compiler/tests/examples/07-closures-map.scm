(define (map1 f lst)
  (if (null? lst)
      '()
      (cons (f (car lst)) (map1 f (cdr lst)))))

(define (sum-list lst)
  (if (null? lst)
      0
      (+ (car lst) (sum-list (cdr lst)))))

(display (sum-list (map1 (lambda (x) (* x x)) (list 1 2 3 4))))
(display "\n")
