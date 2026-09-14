;;; det-mode-demo.lisp -- Edinburgh-notation counterpart to det-mode.lisp.
;;;
;;; det-mode.pl (Edinburgh notation, no annotations at all -- see its own
;;; header) supplies the plain clauses for the same five predicates
;;; det-mode.lisp defines: count-up/3, parity/2, minmax/4, firstof/2,
;;; append/3. This file consults it, then declares each MODE explicitly
;;; from the Lisp side -- the only way to mode-compile a predicate whose
;;; clauses came from Edinburgh source, since that notation has no way to
;;; write the inline +/- annotation det-mode.lisp's own APPEND clause
;;; uses, and CONSULT never goes through the <- macro that annotation-
;;; style detection hooks into anyway (see NOTES.md and det-mode.pl).
;;;
;;; Call the results three ways, exactly as det-mode.lisp's own header
;;; describes:
;;;   * direct compiled function:  (moded-count-up-3 0 10)
;;;   * ordinary query:            (?- (count-up 0 10 ?result))
;;;   * with backtracking:         (?-all (minmax 9 3 ?lo ?hi))

(load "prolog-engine.lisp")
(load "mode-compiler.lisp")
(load "edinburgh-reader.lisp")

(consult "det-mode.pl")

(mode (count-up + + -))
(mode (parity + -))
(mode (minmax + + - -))
(mode (firstof + -))
(mode (append + + -))

(format t "~%det-mode.pl consulted and mode-compiled: count-up/3, parity/2, minmax/4, firstof/2, append/3.~%")

(format t "~%== direct compiled functions ==~%")
(multiple-value-bind (ok out) (moded-count-up-3 0 10)
  (format t "moded-count-up-3(0, 10) = ok=~S out=~S (expect T 10)~%" ok out))
;; NB parity/2 only ever handles the two literal inputs 0 and 1 -- that's
;; a limitation of det-mode.lisp's own original example (a toy predicate,
;; not a real is-N-odd check), faithfully preserved here, not something
;; this port introduced or fixed.
(multiple-value-bind (ok p) (moded-parity-2 1)
  (format t "moded-parity-2(1) = ok=~S p=~S (expect T ODD)~%" ok p))
(multiple-value-bind (ok lo hi) (moded-minmax-4 9 3)
  (format t "moded-minmax-4(9, 3) = ok=~S lo=~S hi=~S (expect T 3 9)~%" ok lo hi))
(multiple-value-bind (ok x) (moded-firstof-2 '(a b c))
  (format t "moded-firstof-2((a b c)) = ok=~S x=~S (expect T A)~%" ok x))
(multiple-value-bind (ok z) (moded-append-3 '(1 2) '(3 4))
  (format t "moded-append-3((1 2), (3 4)) = ok=~S z=~S (expect T (1 2 3 4))~%" ok z))

(format t "~%== ordinary queries, same predicates, same clauses ==~%")
(format t "count-up(0, 10, Result): ") (?- (count-up 0 10 ?result))
(format t "parity(1, P): ") (?- (parity 1 ?p))
(format t "append((1 2), (3 4), Z): ") (?- (append (1 2) (3 4) ?z))

(format t "~%== backtracking with ?-all ==~%")
(format t "minmax(9, 3, Lo, Hi):~%")
(?-all (minmax 9 3 ?lo ?hi))

(sb-ext:exit)
