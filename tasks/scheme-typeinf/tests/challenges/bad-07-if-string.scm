;; bad: if branches used as number after non-number then-branch is selected
;; Always takes then branch; then-branch returns a string used as number.
(let ((v (if #t "nope" 1)))
  (+ v 1))
