;; Rule 1: Once we hit or pass 10, Cut (!) and stop tracking further rules.
(<- (count-up ?n ?out)
    (lisp-eval t (>= ?n 10))
    !
    (unify ?out ?n))

;; Rule 2: Fallback processing rule.
(<- (count-up ?n ?out)
    (lisp-eval ?next (+ ?n 0.01))
    (count-up ?next ?out))

;;(?- (count-up 0 ?result))
