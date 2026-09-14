;; Benchmarks comparing claude-prolog to SWI-Prolog (see bench_swi.pl for
;; the matching SWI side, and NOTES.md's "Performance vs SWI-Prolog"
;; section for the results and analysis). Run with:
;;   sbcl --script bench_claude_prolog.lisp
;;
;; Kept in sync with the engine's current SOLVE-ONE/SOLVE-NEXT/GROUND API
;; (protected-vars, not a bindings alist -- see prolog-engine.lisp's own
;; header comment) and with the v4 anonymous variable _ (see NOTES.md).

(load "prolog-engine.lisp")

;; ---------- Benchmark 1: tail-recursive arithmetic loop ----------
(<- (count-up3 ?n ?stop ?n)
    (lisp-eval t (>= ?n ?stop))
    !)
(<- (count-up3 ?n ?stop ?out)
    (lisp-eval ?next (+ ?n 0.01))
    (count-up3 ?next ?stop ?out))

;; ---------- Benchmark 2: naive reverse (nrev) -- NOT tail-recursive ----------
;; Deliberately run as a size-scaling test rather than a fixed rep count:
;; nrev is the textbook case where a naive bindings representation (a
;; linear alist, only trimmed in exact tail position with zero pending
;; choice points -- v1's design, see NOTES.md) stops being O(1)-per-step
;; and the whole thing goes superlinear. v2's trail-based bindings fixed
;; that; see NOTES.md's v2 section for the before/after numbers.
(<- (myapp nil ?ys ?ys) !)
(<- (myapp (?x . ?xs) ?ys (?x . ?zs)) ! (myapp ?xs ?ys ?zs))
(<- (nrev nil nil) !)
(<- (nrev (?x . ?xs) ?ys) ! (nrev ?xs ?zs) (myapp ?zs (?x) ?ys))
(<- (mklist 0 nil) !)
(<- (mklist ?n (?n . ?t))
    (lisp-eval t (> ?n 0)) !
    (lisp-eval ?n1 (- ?n 1))
    (mklist ?n1 ?t))

;; ---------- Benchmark 3: 8-queens, count all solutions (backtracking) ----
;; Generate-a-permutation-then-test-safety, same algorithm as bench_swi.pl's
;; hand-rolled version (not using any builtin permutation/select). NOTE:
;; my-select's first clause must stay non-deterministic (no cut) -- it's
;; select/3's whole job to offer every element of the list as a candidate
;; on backtracking, which is what lets my-permute enumerate every ordering.
(<- (my-select ?x (?x . ?xs) ?xs))
(<- (my-select ?x (?y . ?ys) (?y . ?zs)) (my-select ?x ?ys ?zs))
(<- (my-permute nil nil) !)
(<- (my-permute ?l (?x . ?xs)) (my-select ?x ?l ?rest) (my-permute ?rest ?xs))
(<- (my-numlist ?lo ?hi nil) (lisp-eval t (> ?lo ?hi)) !)
(<- (my-numlist ?lo ?hi (?lo . ?t))
    (lisp-eval t (<= ?lo ?hi)) !
    (lisp-eval ?lo1 (+ ?lo 1))
    (my-numlist ?lo1 ?hi ?t))
(<- (queens-safe nil) !)
(<- (queens-safe (?q . ?qs)) ! (queens-safe ?qs ?q 1) (queens-safe ?qs))
;; The two "don't care" args here can now both be written _: the engine
;; gives _ real standard-Prolog anonymous-variable semantics (every
;; occurrence is its own fresh, unrelated variable -- see NOTES.md's v4
;; section), so two _'s no longer force those two call-time values to
;; unify with each other the way an ordinary named variable repeated
;; twice would. (Earlier versions of this file worked around the lack of
;; that feature with two distinctly-named variables, ?ignore1/?ignore2.)
(<- (queens-safe nil _ _) !)
(<- (queens-safe (?q . ?qs) ?q0 ?d0)
    (lisp-eval ?sum (+ ?q ?d0)) (/= ?q0 ?sum)
    (lisp-eval ?diff (- ?q ?d0)) (/= ?q0 ?diff)
    (lisp-eval ?d1 (+ ?d0 1))
    (queens-safe ?qs ?q0 ?d1))
(<- (queens ?n ?qs) (my-numlist 1 ?n ?ns) (my-permute ?ns ?qs) (queens-safe ?qs))

(defun count-all-solutions (query)
  (let ((count 0))
    (multiple-value-bind (protected-vars choices ok) (solve-one query)
      (loop while ok do
        (incf count)
        (multiple-value-bind (pv2 c2 ok2) (solve-next choices protected-vars)
          (setf protected-vars pv2 choices c2 ok ok2))))
    count))

(format t "~%== Benchmark 1: (count-up3 0 10000 ?result), 1,000,000 tail-recursive steps ==~%")
(time (?- (count-up3 0 10000 ?result)))

(format t "~%== Benchmark 2: nrev size scaling (doubling L) ==~%")
(dolist (n '(10 20 40 80 160))
  (multiple-value-bind (protected-vars choices ok) (solve-one (list 'mklist n '?list))
    (declare (ignore choices ok))
    (let ((lst (ground (first protected-vars)))
          (start (get-internal-real-time)))
      (solve-one (list 'nrev lst '?ys))
      (format t "L=~D: ~,4Fs~%" n
              (/ (- (get-internal-real-time) start) 1.0 internal-time-units-per-second)))))

(format t "~%== Benchmark 3: 8-queens, count all solutions (expect 92) ==~%")
(time (format t "solutions=~D~%" (count-all-solutions '(queens 8 ?qs))))
