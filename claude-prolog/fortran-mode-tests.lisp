(load "prolog-engine.lisp")
(load "mode-compiler.lisp")

(format t "~%== inline +/- syntax: count-up3, no explicit (mode ...) call at all ==~%")
;; This file's convention (same as the explicit MODE macro -- see mode-
;; compiler.lisp's banner comment: there is only one polarity, not two):
;; + = input, - = output, ?x = ordinary two-way var. So count-up3(n, stop,
;; out) with n/stop as inputs and out as output is written +n +stop -out.
(<- (count-up3f +n +stop -out)
    (lisp-eval t (>= ?n ?stop))
    !
    (unify ?out ?n))
(<- (count-up3f +n +stop -out)
    (lisp-eval ?next (+ ?n 0.01))
    (count-up3f ?next ?stop ?out))
;; NOTE: no (mode ...) call -- both clauses are fully inline-annotated and
;; every position resolves immediately, so MODED-COUNT-UP3F-3 should
;; already exist by the time we get here.
(format t "moded-count-up3f-3(0, 100) = ~S (expect T 100.00295)~%"
        (multiple-value-list (moded-count-up3f-3 0 100)))
(format t "cross-check against interpreted engine: ")
(?- (count-up3f 0 100 ?result))

(format t "~%== inline syntax generates identical stored clauses to plain ?-syntax ==~%")
;; count-up3f's clauses, once stripped, should look exactly like count-up3's
;; (from mode-tests.lisp/bench-mode.lisp) -- verify by querying it the
;; ORDINARY (interpreted/v6-compiled) way too, not just via the direct
;; moded function, proving <-'s inline detection didn't leave any residue
;; the general engine chokes on.
(?-all (count-up3f 0 0.03 ?result))

(format t "~%== stack safety / TCO check for the inline-syntax version ==~%")
(format t "moded-count-up3f-3(0, 10000) via inline syntax = ~S~%"
        (multiple-value-list (moded-count-up3f-3 0 10000)))
(format t "(if that printed instead of crashing, SBCL TCO'd this exactly like the explicit-mode version)~%")

(format t "~%== benchmark: inline-syntax moded function vs explicit-mode moded function ==~%")
(<- (count-up3 ?n ?stop ?out)
    (lisp-eval t (>= ?n ?stop))
    !
    (unify ?out ?n))
(<- (count-up3 ?n ?stop ?out)
    (lisp-eval ?next (+ ?n 0.01))
    (count-up3 ?next ?stop ?out))
(mode (count-up3 + + -))
(format t "explicit (mode ...), 1,000,000 steps:~%")
(time (moded-count-up3-3 0 10000))
(format t "inline +/- syntax, 1,000,000 steps (same generated machinery, expect identical):~%")
(time (moded-count-up3f-3 0 10000))

(format t "~%== inline syntax: 3-output predicate via multiple-value-bind ==~%")
(<- (triplef +a -x -y -z)
    (lisp-eval ?x (+ ?a 1))
    (lisp-eval ?y (+ ?a 2))
    (lisp-eval ?z (+ ?a 3)))
(multiple-value-bind (ok x y z) (moded-triplef-4 10)
  (format t "moded-triplef-4(10) via multiple-value-bind: ok=~S x=~S y=~S z=~S~%" ok x y z)
  (format t "expect: ok=T x=11 y=12 z=13 -- ~:[MISMATCH~;correct~]~%"
          (and ok (= x 11) (= y 12) (= z 13))))

(format t "~%== inline syntax: 4-output predicate via multiple-value-bind ==~%")
(<- (quadf +a -w -x -y -z)
    (unify ?w ?a)
    (lisp-eval ?x (* ?a 2))
    (lisp-eval ?y (* ?a 3))
    (lisp-eval ?z (* ?a 4)))
(multiple-value-bind (ok w x y z) (moded-quadf-5 7)
  (format t "moded-quadf-5(7) via multiple-value-bind: ok=~S w=~S x=~S y=~S z=~S~%" ok w x y z)
  (format t "expect: ok=T w=7 x=14 y=21 z=28 -- ~:[MISMATCH~;correct~]~%"
          (and ok (= w 7) (= x 14) (= y 21) (= z 28))))

(format t "~%== inline syntax: tail-call chaining (relay calls triplef as its last goal) ==~%")
(<- (relayf +a -x -y -z) (triplef ?a ?x ?y ?z))
(multiple-value-bind (ok x y z) (moded-relayf-4 20)
  (format t "moded-relayf-4(20) via multiple-value-bind: ok=~S x=~S y=~S z=~S~%" ok x y z)
  (format t "expect: ok=T x=21 y=22 z=23 -- ~:[MISMATCH~;correct~]~%"
          (and ok (= x 21) (= y 22) (= z 23))))

(format t "~%== underscore in a head position, inline syntax ==~%")
;; _ carries no +/- prefix (nothing to annotate), so -- exactly like a
;; literal position -- its direction can't be inferred from inline syntax
;; alone; this one clause alone leaves *det-mode-progress* at (+ NIL -)
;; for ignore-secondf/3, so it does NOT auto-compile (same limitation as
;; the parityf case below), and needs the explicit MODE fallback.
(<- (ignore-secondf +x _ -y) (unify ?y ?x))
(format t "moded-ignore-secondf-3 bound before explicit mode? ~S (expect NIL)~%"
        (fboundp 'moded-ignore-secondf-3))
(mode (ignore-secondf + + -))
(format t "moded-ignore-secondf-3(1, whatever) = ~S (expect T 1)~%"
        (multiple-value-list (moded-ignore-secondf-3 1 'whatever)))

(format t "~%== error case: mixing +/- annotated vars with a plain ?x in one head ==~%")
(handler-case
    (progn
      (eval '(<- (badmix +x ?y -z) (unify ?y ?x) (unify ?z ?x)))
      (format t "NO ERROR RAISED -- BUG~%"))
  (error (e) (format t "correctly rejected: ~A~%" e)))

(format t "~%== error case: two clauses give conflicting inline directions for the same position ==~%")
;; first clause says position 2 is OUTPUT (-y), second says it's INPUT
;; (+y) -- for the SAME predicate/arity -- must error, not silently pick
;; one.
(handler-case
    (progn
      (eval '(<- (badconflict +x -y) (unify ?y ?x)))
      (eval '(<- (badconflict +x +y) (unify ?y ?x)))
      (format t "NO ERROR RAISED -- BUG~%"))
  (error (e) (format t "correctly rejected: ~A~%" e)))

(format t "~%== literal-position limitation: a predicate whose output is always a literal never auto-resolves via inline syntax alone ==~%")
;; Every clause's second (output-by-intent) position is a bare literal
;; (EVEN/ODD), never an annotated variable -- so *det-mode-progress* for
;; parityf/2 stays (+ NIL) forever; MODED-PARITYF-2 is correctly never
;; auto-generated. The clauses are still fully usable the ordinary way,
;; and the explicit MODE macro remains a working manual fallback (the
;; stored clauses are plain ?-syntax underneath either way).
(<- (parityf +n even) (lisp-eval t (= ?n 0)) !)
(<- (parityf +n odd) (lisp-eval t (= ?n 1)) !)
(format t "moded-parityf-2 bound as a function? ~S (expect NIL -- never auto-compiled)~%"
        (fboundp 'moded-parityf-2))
(format t "ordinary query still works: ")
(?- (parityf 0 ?result))
(format t "explicit (mode ...) fallback works on the same inline-declared clauses:~%")
(mode (parityf + -))
(format t "moded-parityf-2(0) = ~S (expect T EVEN)~%" (multiple-value-list (moded-parityf-2 0)))
(format t "moded-parityf-2(1) = ~S (expect T ODD)~%" (multiple-value-list (moded-parityf-2 1)))

(format t "~%all Fortran-style inline mode-syntax tests done~%")
(sb-ext:exit)
