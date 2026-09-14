;; Non-deterministic append relation.
;;
;; app(?xs, ?ys, ?zs) means:
;;   list ?zs is the result of appending list ?xs to list ?ys.

;; Base case:
;; Appending the empty list to ?ys gives ?ys.
(<- (app nil ?ys ?ys))

;; Recursive case:
;; If appending ?xs to ?ys gives ?zs, then appending (?h . ?xs)
;; to ?ys gives (?h . ?zs).
(<- (app (?h . ?xs) ?ys (?h . ?zs))
    (app ?xs ?ys ?zs))

;; Examples:
;;
;; Forward append:
;;   (?- (app (1 2) (3 4) ?result))
;;   => ?RESULT = (1 2 3 4)
;;
;; Relational / non-deterministic split:
;;   (?- (app ?left ?right (1 2 3)))
;;   first answer:
;;   => ?LEFT = NIL
;;      ?RIGHT = (1 2 3)
;;
;; Other valid answers include:
;;   ?LEFT = (1)     ?RIGHT = (2 3)
;;   ?LEFT = (1 2)   ?RIGHT = (3)
;;   ?LEFT = (1 2 3) ?RIGHT = NIL
;; ?-all walks the remained choice points
