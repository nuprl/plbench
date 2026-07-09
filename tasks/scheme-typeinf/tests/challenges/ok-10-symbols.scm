;; ok: symbols via quote (homogeneous symbol list)
(let ((xs (quote (a b c))))
  (symbol? (car xs)))
