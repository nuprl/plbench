;; Verifier metacircular MiniScheme interpreter (subset).
;; Load with the host:
;;   /app/minischeme -l /tests/mceval.scm -e '(display (ms-eval (quote (+ 1 2)) (ms-initial-env)))'
;;
;; API:
;;   (ms-initial-env)              -> initial environment
;;   (ms-eval expr env)            -> value of expr in env
;;
;; Environments are lists of bindings: ((name value) ...).
;; Closures are lists: (closure (params...) body env).
;; Builtins are lists: (builtin name).

(define (ms-tagged? x tag)
  (and (pair? x) (eq? (car x) tag)))

(define (ms-closure params body env)
  (list 'closure params body env))

(define (ms-closure? x) (ms-tagged? x 'closure))
(define (ms-closure-params c) (list-ref c 1))
(define (ms-closure-body c) (list-ref c 2))
(define (ms-closure-env c) (list-ref c 3))

(define (ms-builtin name) (list 'builtin name))
(define (ms-builtin? x) (ms-tagged? x 'builtin))
(define (ms-builtin-name b) (list-ref b 1))

(define (ms-bind-name b) (car b))
(define (ms-bind-value b) (list-ref b 1))

(define (ms-lookup name env)
  (cond
    ((null? env) (error "ms-eval: unbound variable"))
    ((eq? (ms-bind-name (car env)) name) (ms-bind-value (car env)))
    (else (ms-lookup name (cdr env)))))

(define (ms-extend params args env)
  (if (null? params)
      (if (null? args)
          env
          (error "ms-eval: too many arguments"))
      (if (null? args)
          (error "ms-eval: too few arguments")
          (cons (list (car params) (car args))
                (ms-extend (cdr params) (cdr args) env)))))

(define (ms-truthy? v)
  (if (eq? v #f) #f #t))

(define (ms-eval-seq exps env)
  (if (null? (cdr exps))
      (ms-eval (car exps) env)
      (begin
        (ms-eval (car exps) env)
        (ms-eval-seq (cdr exps) env))))

(define (ms-eval-and exps env)
  (cond
    ((null? exps) #t)
    ((null? (cdr exps)) (ms-eval (car exps) env))
    (else
     (if (ms-truthy? (ms-eval (car exps) env))
         (ms-eval-and (cdr exps) env)
         #f))))

(define (ms-eval-or exps env)
  (cond
    ((null? exps) #f)
    ((null? (cdr exps)) (ms-eval (car exps) env))
    (else
     (let ((v (ms-eval (car exps) env)))
       (if (ms-truthy? v) v (ms-eval-or (cdr exps) env))))))

(define (ms-eval-cond clauses env)
  (if (null? clauses)
      (error "ms-eval: cond exhausted")
      (let ((clause (car clauses)))
        (if (eq? (car clause) 'else)
            (ms-eval (list-ref clause 1) env)
            (if (ms-truthy? (ms-eval (car clause) env))
                (ms-eval (list-ref clause 1) env)
                (ms-eval-cond (cdr clauses) env))))))

(define (ms-binding-names bs)
  (if (null? bs)
      '()
      (cons (car (car bs)) (ms-binding-names (cdr bs)))))

(define (ms-binding-vals bs env)
  (if (null? bs)
      '()
      (cons (ms-eval (list-ref (car bs) 1) env)
            (ms-binding-vals (cdr bs) env))))

(define (ms-eval-let bindings body env)
  (ms-eval body
           (ms-extend (ms-binding-names bindings)
                      (ms-binding-vals bindings env)
                      env)))

(define (ms-map-eval exps env)
  (if (null? exps)
      '()
      (cons (ms-eval (car exps) env)
            (ms-map-eval (cdr exps) env))))

(define (ms-prim-apply name args)
  (cond
    ((eq? name '+) (apply + args))
    ((eq? name '-) (apply - args))
    ((eq? name '*) (apply * args))
    ((eq? name '/) (apply / args))
    ((eq? name '=) (apply = args))
    ((eq? name '<) (apply < args))
    ((eq? name '>) (apply > args))
    ((eq? name '<=) (apply <= args))
    ((eq? name '>=) (apply >= args))
    ((eq? name 'cons) (cons (car args) (list-ref args 1)))
    ((eq? name 'car) (car (car args)))
    ((eq? name 'cdr) (cdr (car args)))
    ((eq? name 'list) args)
    ((eq? name 'null?) (null? (car args)))
    ((eq? name 'pair?) (pair? (car args)))
    ((eq? name 'list?) (list? (car args)))
    ((eq? name 'length) (length (car args)))
    ((eq? name 'append) (apply append args))
    ((eq? name 'list-ref) (list-ref (car args) (list-ref args 1)))
    ((eq? name 'not) (not (car args)))
    ((eq? name 'eq?) (eq? (car args) (list-ref args 1)))
    ((eq? name 'equal?) (equal? (car args) (list-ref args 1)))
    ((eq? name 'number?) (number? (car args)))
    ((eq? name 'integer?) (integer? (car args)))
    ((eq? name 'boolean?) (boolean? (car args)))
    ((eq? name 'symbol?) (symbol? (car args)))
    ((eq? name 'string?) (string? (car args)))
    ((eq? name 'vector?) (vector? (car args)))
    ((eq? name 'procedure?)
     (or (ms-closure? (car args)) (ms-builtin? (car args))))
    ((eq? name 'vector) (apply vector args))
    ((eq? name 'vector-ref) (vector-ref (car args) (list-ref args 1)))
    ((eq? name 'vector-length) (vector-length (car args)))
    ((eq? name 'string-length) (string-length (car args)))
    ((eq? name 'string-append) (apply string-append args))
    ((eq? name 'display) (display (car args)))
    ((eq? name 'error) (error (car args)))
    (else (error "ms-eval: unknown builtin"))))

(define (ms-apply proc args)
  (cond
    ((ms-builtin? proc) (ms-prim-apply (ms-builtin-name proc) args))
    ((ms-closure? proc)
     (ms-eval (ms-closure-body proc)
              (ms-extend (ms-closure-params proc) args (ms-closure-env proc))))
    (else (error "ms-eval: apply non-procedure"))))

(define (ms-eval expr env)
  (cond
    ((number? expr) expr)
    ((boolean? expr) expr)
    ((string? expr) expr)
    ((symbol? expr) (ms-lookup expr env))
    ((pair? expr)
     (let ((op (car expr)))
       (cond
         ((eq? op 'quote)
          (list-ref expr 1))
         ((eq? op 'lambda)
          (ms-closure (list-ref expr 1) (list-ref expr 2) env))
         ((eq? op 'if)
          (if (ms-truthy? (ms-eval (list-ref expr 1) env))
              (ms-eval (list-ref expr 2) env)
              (ms-eval (list-ref expr 3) env)))
         ((eq? op 'begin)
          (ms-eval-seq (cdr expr) env))
         ((eq? op 'and)
          (ms-eval-and (cdr expr) env))
         ((eq? op 'or)
          (ms-eval-or (cdr expr) env))
         ((eq? op 'cond)
          (ms-eval-cond (cdr expr) env))
         ((eq? op 'let)
          (ms-eval-let (list-ref expr 1) (list-ref expr 2) env))
         (else
          (ms-apply (ms-eval op env)
                    (ms-map-eval (cdr expr) env))))))
    (else (error "ms-eval: cannot evaluate"))))

(define (ms-bind-prims names env)
  (if (null? names)
      env
      (cons (list (car names) (ms-builtin (car names)))
            (ms-bind-prims (cdr names) env))))

(define (ms-initial-env)
  (ms-bind-prims
   '(+ - * / = < > <= >= cons car cdr list null? pair? list? length append
     list-ref not eq? equal? number? integer? boolean? symbol? string?
     vector? procedure? vector vector-ref vector-length string-length
     string-append display error)
   '()))
