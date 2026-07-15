;; bad: eq? uses object identity for floats.  These separately parsed float
;; values are not identical, so evaluation reaches the ill-typed else branch.
(if (eq? 0.0 0.0)
    "ok"
    (+ "bad" 1))
