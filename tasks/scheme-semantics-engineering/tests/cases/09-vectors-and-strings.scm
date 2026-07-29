(display
  (let ((values (vector "ab" "cd" "ef")))
    (string-append
      (vector-ref values 0)
      (vector-ref values 2)
      (string-ref "xyz" 1))))
