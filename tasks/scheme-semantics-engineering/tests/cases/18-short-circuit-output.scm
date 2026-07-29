(begin
  (and #f (display "unreachable-and"))
  (or #t (display "unreachable-or"))
  (and (begin (display "seen") #t) 77))
