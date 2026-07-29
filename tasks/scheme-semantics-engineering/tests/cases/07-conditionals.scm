(display
  (list
    (and #t 1 2)
    (or #f #f 9)
    (cond ((> 1 2) 'bad)
          ((= 3 3) 'good)
          (else 'bad))))
