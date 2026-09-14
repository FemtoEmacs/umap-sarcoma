;; Deterministic list length relation.
;;
;; list-len(?xs, ?n) means:
;;   ?n is the number of elements in the proper list ?xs.

;; Base case:
;; The empty list has length 0.
(<- (list-len nil 0))

;; Recursive case:
;; If ?tail has length ?tail-n, then (?head . ?tail) has length
;; ?tail-n + 1.
(<- (list-len (?head . ?tail) ?n)
    (list-len ?tail ?tail-n)
    (lisp-eval ?n (+ ?tail-n 1)))

;; Examples:
;;
;;   (?- (list-len nil ?n))
;;   => ?N = 0
;;
;;   (?- (list-len (a b c d) ?n))
;;   => ?N = 4
