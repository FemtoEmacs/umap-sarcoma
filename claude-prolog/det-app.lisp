(callable car)
(callable cdr)
(callable cons)
(callable reverse)



(<- (append nil +y +y))
(<- (append (+x . +xs) +y (-x . -z)) (append ?xs ?y ?z))


(<- (doubled3 nil ?acc ?out) (lisp-eval ?out (reverse ?acc)))
(<- (doubled3 ?lst ?acc ?out)
    (lisp-eval ?h (car ?lst))
    (lisp-eval ?t (cdr ?lst))
    (lisp-eval ?h2 (* ?h 2))
    (lisp-eval ?acc1 (cons ?h2 ?acc))
    (doubled3 ?t ?acc1 ?out))
