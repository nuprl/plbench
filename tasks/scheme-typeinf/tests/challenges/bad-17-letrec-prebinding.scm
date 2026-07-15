;; bad: MiniScheme pre-binds each letrec name to #f before evaluating its
;; initializer, so this initializer adds a Boolean to an integer.
(letrec ((x (+ x 1)))
  x)
