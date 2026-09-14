;;; infix-is-tests.lisp -- verification for read-goal's new infix `is'
;;; spelling (2026-09-14 later still): X is Expr, alongside the existing
;;; is(X, Expr) prefix/compound-term spelling, both producing the identical
;;; (IS X Expr) shape BUILTIN-STEP already dispatches on.
;;; Run with: sbcl --script infix-is-tests.lisp

(load "prolog-engine.lisp")
(load "edinburgh-reader.lisp")

(defun edinburgh-goal-term (text)
  "Like EDINBURGH-TERM, but parses via READ-GOAL rather than READ-TERM --
   the infix `is' hook lives in READ-GOAL only (goal position, matching
   the existing `=' / `=:=' / etc. surface rewrites), so this is what a
   real clause body or ?-/EDINBURGH-QUERY actually sees, unlike bare
   EDINBURGH-TERM, which has no notion of goals at all."
  (let ((ps (ps-make text "<goal>")))
    (let ((goal (read-goal ps)))
      (ps-skip-layout ps)
      (unless (ps-eof-p ps) (ps-error ps "unexpected trailing input after goal"))
      goal)))

(format t "== both spellings parse to the identical term ==~%")
(format t "prefix   is(X, (+ 1 2)):    ~S~%" (edinburgh-goal-term "is(X, (+ 1 2))"))
(format t "infix    X is (+ 1 2):      ~S~%" (edinburgh-goal-term "X is (+ 1 2)"))
(format t "(expect both (IS ?X (+ 1 2)))~%")

(format t "~%== infix `is' actually runs, both as a bare-paren Lisp escape and~%")
(format t "   with a plain number on the right ==~%")
(format t "?- X is (+ 2 3): ") (edinburgh-query "X is (+ 2 3)")
(format t "  (expect ?X = 5)~%")
(format t "?- X is 7: ") (edinburgh-query "X is 7")
(format t "  (expect ?X = 7)~%")

(format t "~%== infix `is' in a clause body, exactly like det-mode.pl's~%")
(format t "   prefix-spelled count-up/3, just with the other spelling ==~%")
(consult-edinburgh-string "
count-up2(N, Stop, Out) :- >=(N, Stop), !, =(Out, N).
count-up2(N, Stop, Out) :- Next is (+ N 1), count-up2(Next, Stop, Out).
")
(format t "?- count-up2(0, 5, Out): ") (edinburgh-query "count-up2(0, 5, Out)")
(format t "  (expect ?Out = 5)~%")

(format t "~%== register-callable-backed function on the right, exactly~%")
(format t "   sarcoma-setup.pl's env-value(epochs, V) shape ==~%")
(defun double-it (n) (* 2 n))
(register-callable 'double-it)
(format t "?- V is (double-it 21): ") (edinburgh-query "V is (double-it 21)")
(format t "  (expect ?V = 42)~%")

(format t "~%== `is(X,Y)' tight-paren stays the ordinary compound-term parse,~%")
(format t "   completely unaffected by the new infix rule ==~%")
(format t "~S (expect (IS ?X 5), same shape, parsed the old way)~%" (edinburgh-goal-term "is(X, 5)"))

(format t "~%== the one deliberately-unsupported edge case: a tight-paren `is('~%")
(format t "   right after a term is NOT infix (two terms in a row, same~%")
(format t "   'no legal connector' rule as everywhere else in this reader) --~%")
(format t "   a clear syntax error, never a silent misparse ==~%")
(handler-case (progn (edinburgh-goal-term "X is(A,B)") (format t "SHOULD HAVE ERRORED~%"))
  (edinburgh-syntax-error (c) (format t "correctly errored: ~A~%" c)))

(format t "~%All infix-is checks ran.~%")
(sb-ext:exit)
