;;;; sieve.lisp -- GENERATED from swi/sieve.pl by bench/pl2lispy.lisp; do not edit.

(progn (declare-dynamic '(/ prime 1)))
(progn (declare-dynamic '(/ candidate 1)))
(<- (top) (clean) (primes 10000) !)
(<- (clean) (retractall (prime _)) (retractall (candidate _)))
(<- (primes ?n) (\\+ (:or (:and (range 2 ?n ?i) (\\+ (assertz (candidate ?i)))))) (sieve ?n))
(<- (sieve ?max) (retract (candidate ?first)) ! (assertz (prime ?first)) (< ?first ?max)
 (sieve ?first 2 ?max) (sieve ?max))
(<- (sieve _))
(<- (sieve ?n ?mul ?max) (is ?i (* ?n ?mul)) (<= ?i ?max) !
 (:or (retract (candidate ?i)) -> true true) (is ?mul2 (+ ?mul 1)) (sieve ?n ?mul2 ?max))
(<- (sieve _ _ _))
(<- (range ?low ?high ?low) (<= ?low ?high))
(<- (range ?low ?high ?i) (is ?low2 (+ ?low 1)) (<= ?low2 ?high) (range ?low2 ?high ?i))
