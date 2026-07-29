(display
  (equal?
    '(one (2 #t) #(three "four"))
    (list 'one (list 2 #t) (vector 'three "four"))))
