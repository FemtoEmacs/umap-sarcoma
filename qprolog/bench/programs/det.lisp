;;;; det.lisp -- GENERATED from swi/det.pl by bench/pl2lispy.lisp; do not edit.

(<- (top) (numlist 1 1000 ?list) (forall (between 1 10 _) (slist ?list 0 _)) fail)
(<- (top) (rdet 100000))
(<- (top))
(<- (slist nil ?sum0 ?sum) ! (unify ?sum ?sum0))
(<- (slist (?h . ?t) ?sum0 ?sum) ! (is ?sum1 (+ ?sum0 ?h)) (slist ?t ?sum1 ?sum))
(<- (rdet 0) ! true)
(<- (rdet ?n) ! (p) ! (is ?n1 (- ?n 1)) (rdet ?n1))
(<- (p))
