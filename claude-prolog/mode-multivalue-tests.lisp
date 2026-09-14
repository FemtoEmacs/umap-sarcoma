(load "prolog-engine.lisp")
(load "mode-compiler.lisp")

(format t "~%== three output values ==~%")
;; (triple ?a ?x ?y ?z) :- x=a+1, y=a+2, z=a+3.  mode (+ - - -)
(<- (triple ?a ?x ?y ?z)
    (lisp-eval ?x (+ ?a 1))
    (lisp-eval ?y (+ ?a 2))
    (lisp-eval ?z (+ ?a 3)))
(mode (triple + - - -))
(multiple-value-bind (ok x y z) (moded-triple-4 10)
  (format t "moded-triple-4(10) via multiple-value-bind: ok=~S x=~S y=~S z=~S~%" ok x y z)
  (format t "expect: ok=T x=11 y=12 z=13 -- ~:[MISMATCH~;correct~]~%"
          (and ok (= x 11) (= y 12) (= z 13))))

(format t "~%== four output values ==~%")
;; (quad ?a ?w ?x ?y ?z) :- w=a, x=a*2, y=a*3, z=a*4.  mode (+ - - - -)
(<- (quad ?a ?w ?x ?y ?z)
    (unify ?w ?a)
    (lisp-eval ?x (* ?a 2))
    (lisp-eval ?y (* ?a 3))
    (lisp-eval ?z (* ?a 4)))
(mode (quad + - - - -))
(multiple-value-bind (ok w x y z) (moded-quad-5 7)
  (format t "moded-quad-5(7) via multiple-value-bind: ok=~S w=~S x=~S y=~S z=~S~%" ok w x y z)
  (format t "expect: ok=T w=7 x=14 y=21 z=28 -- ~:[MISMATCH~;correct~]~%"
          (and ok (= w 7) (= x 14) (= y 21) (= z 28))))

(format t "~%== a second clause (deterministic choice) still returns the right count/values ==~%")
;; two clauses, base case (0 outputs computed by arithmetic, just literals)
;; and general case (three real outputs), same arity/mode throughout.
(<- (triple2 0 zero zero zero) !)
(<- (triple2 ?a ?x ?y ?z)
    (lisp-eval t (> ?a 0)) !
    (lisp-eval ?x (+ ?a 100))
    (lisp-eval ?y (+ ?a 200))
    (lisp-eval ?z (+ ?a 300)))
(mode (triple2 + - - -))
(multiple-value-bind (ok x y z) (moded-triple2-4 0)
  (format t "moded-triple2-4(0) via multiple-value-bind: ok=~S x=~S y=~S z=~S (expect T ZERO ZERO ZERO)~%" ok x y z))
(multiple-value-bind (ok x y z) (moded-triple2-4 5)
  (format t "moded-triple2-4(5) via multiple-value-bind: ok=~S x=~S y=~S z=~S (expect T 105 205 305)~%" ok x y z))

(format t "~%== chaining: a moded predicate TAIL-CALLING another moded predicate with 3 outputs ==~%")
;; (relay ?a ?x ?y ?z) :- triple(?a, ?x, ?y, ?z).   -- a pure pass-through
;; tail call, exercising the multi-output tail-call path (not just the
;; direct-return path already covered above).
(<- (relay ?a ?x ?y ?z) (triple ?a ?x ?y ?z))
(mode (relay + - - -))
(multiple-value-bind (ok x y z) (moded-relay-4 20)
  (format t "moded-relay-4(20) via multiple-value-bind: ok=~S x=~S y=~S z=~S~%" ok x y z)
  (format t "expect: ok=T x=21 y=22 z=23 -- ~:[MISMATCH~;correct~]~%"
          (and ok (= x 21) (= y 22) (= z 23))))

(format t "~%== chaining: tail-call relay with 4 outputs ==~%")
(<- (relay4 ?a ?w ?x ?y ?z) (quad ?a ?w ?x ?y ?z))
(mode (relay4 + - - - -))
(multiple-value-bind (ok w x y z) (moded-relay4-5 9)
  (format t "moded-relay4-5(9) via multiple-value-bind: ok=~S w=~S x=~S y=~S z=~S~%" ok w x y z)
  (format t "expect: ok=T w=9 x=18 y=27 z=36 -- ~:[MISMATCH~;correct~]~%"
          (and ok (= w 9) (= x 18) (= y 27) (= z 36))))

(format t "~%all multi-value tests done~%")
(sb-ext:exit)
