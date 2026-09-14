;; Rule 1: Once we hit or pass the requested stop number, cut (!) and return.
(<- (count-up ?n ?stop ?s ?s)
    (lisp-eval t (>= ?n ?stop))
    !)

;; Rule 2: Keep counting upward by 0.01 until the stop rule succeeds.
(<- (count-up ?n ?stop ?s ?out)
    (lisp-eval ?next (+ ?n 0.01))
    (lisp-eval ?s1 (+ ?s 0.02))
    (count-up ?next ?stop ?s1 ?out))

;; Example:
;;(?- (count-up 0 100 0 ?result))
