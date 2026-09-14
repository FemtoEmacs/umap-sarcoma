;; Rule 1: Once we hit or pass the requested stop number, cut (!) and return.
(<- (count-up3 ?n ?stop ?out)
    (lisp-eval t (>= ?n ?stop))
    !
    (unify ?out ?n))

;; Rule 2: Keep counting upward by 0.01 until the stop rule succeeds.
(<- (count-up3 ?n ?stop ?out)
    (lisp-eval ?next (+ ?n 0.01))
    (count-up3 ?next ?stop ?out))

;; Example:
;;(?- (count-up3 0 100 ?result))
