(callable car)
(callable cdr)
(callable cons)
(callable reverse)

(<- (listsum nil +acc -sum) (unify ?sum ?acc))
(<- (listsum +lst +acc -sum)
    (lisp-eval ?h (car ?lst))
    (lisp-eval ?t (cdr ?lst))
    (lisp-eval ?acc1 (+ ?acc ?h))
    (listsum ?t ?acc1 ?sum))

;;(?- (listsum-check (1 2 3 4 5) 0 ?result))
