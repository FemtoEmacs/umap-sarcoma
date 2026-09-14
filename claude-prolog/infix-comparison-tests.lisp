;;; infix-comparison-tests.lisp -- verification for read-goal's generalized
;;; infix-operator table (2026-09-14, later still): is, =, =:=, =\=, =<, <,
;;; >, >= can now ALL be written infix, not just prefix/compound-term.
;;; Also demonstrates the actually-separate question Eduardo raised
;;; alongside this ("aren't these more complex, since they can combine
;;; with and/or?") -- see the last section: combining comparisons at goal-
;;; BODY level (plain comma-separated goals) has no ambiguity at all and
;;; needs nothing new; combining them as a single TERM (e.g. inside
;;; FINDALL's Goal argument) is a real, separate, still-unimplemented
;;; limitation that exists identically whether comparisons are spelled
;;; prefix or infix -- infix spelling neither causes nor fixes it.
;;; Run with: sbcl --script infix-comparison-tests.lisp

(load "prolog-engine.lisp")
(load "edinburgh-reader.lisp")

(defun goal-of (text) (edinburgh-goal-term-for-test text))
(defun edinburgh-goal-term-for-test (text)
  (let ((ps (ps-make text "<goal>")))
    (let ((goal (read-goal ps)))
      (ps-skip-layout ps)
      (unless (ps-eof-p ps) (ps-error ps "unexpected trailing input after goal"))
      goal)))

(format t "== every one of the 7 comparators: infix parses to the same~%")
(format t "   shape the existing prefix/compound-term spelling produces ==~%")
(dolist (pair '(("X = Y" "=(X, Y)")
                ("X =:= Y" "=:=(X, Y)")
                ("X =\\= Y" "=\\=(X, Y)")
                ("X =< Y" "=<(X, Y)")
                ("X < Y" "<(X, Y)")
                ("X > Y" ">(X, Y)")
                ("X >= Y" ">=(X, Y)")))
  (let ((infix (goal-of (first pair))) (prefix (goal-of (second pair))))
    (format t "~24A -> ~14S   ~24A -> ~14S   ~:[MISMATCH!!~;match~]~%"
            (first pair) infix (second pair) prefix (equal infix prefix))))

(format t "~%== they actually run, infix-spelled, exactly like the prefix~%")
(format t "   forms already used throughout det-mode.pl etc. ==~%")
(format t "?- 3 =< 5, 3 < 5, 5 >= 3, 5 > 3, 3 =:= 3, 3 =\\= 4, X = ok: ")
(edinburgh-query "3 =< 5, 3 < 5, 5 >= 3, 5 > 3, 3 =:= 3, 3 =\\= 4, X = ok")
(format t "  (expect ?X = OK -- every comparator true, X unified last)~%")

(format t "~%== tight-paren stays the ordinary compound-term parse for all 7,~%")
(format t "   completely unaffected ==~%")
(format t "?- >=(5, 3): ") (edinburgh-query ">=(5, 3)")
(format t "  (expect: succeeds silently -- no bindings to print)~%")

(format t "~%== a real det-mode-style clause, written with infix comparators~%")
(format t "   AND infix `is' together, in the same body ==~%")
(consult-edinburgh-string "
count-up4(N, Stop, Out) :- N >= Stop, !, Out = N.
count-up4(N, Stop, Out) :- Next is (+ N 1), count-up4(Next, Stop, Out).
")
(format t "?- count-up4(0, 5, Out): ") (edinburgh-query "count-up4(0, 5, Out)")
(format t "  (expect ?Out = 5)~%")

(format t "~%== chaining is deliberately NOT supported -- 'X < Y < Z' stops~%")
(format t "   after the first comparator, leaving '< Z' as trailing input,~%")
(format t "   which is a clear syntax error, not a silent misparse ==~%")
(handler-case (progn (goal-of "X < Y < Z") (format t "SHOULD HAVE ERRORED~%"))
  (edinburgh-syntax-error (c) (format t "correctly errored: ~A~%" c)))

(format t "~%== goal-BODY combination (plain comma, ',' as pure separator)~%")
(format t "   has NO ambiguity at all, infix or prefix -- comparisons are~%")
(format t "   just flat goals in a list, never nested sub-terms ==~%")
(format t "?- 1 < 2, 2 < 3, 3 < 4: ") (edinburgh-query "1 < 2, 2 < 3, 3 < 4")
(format t "  (expect: yes, no bindings)~%")

(format t "~%== bare 'and'/'or', or ';', between two comparisons: none of~%")
(format t "   these are keywords/operators in this grammar at all, so all~%")
(format t "   three are a clean syntax error, never a silent misparse or~%")
(format t "   an accidental long chain -- the safe 'and' that already~%")
(format t "   exists is plain ',' between separate goals (just above) ==~%")
(dolist (text '("3 < 5 and 4 < 5" "3 < 5 or 4 < 5" "3 < 5 ; 4 < 5"))
  (format t "~30A -> " text)
  (handler-case (progn (edinburgh-query text) (format t "SHOULD HAVE ERRORED~%"))
    (edinburgh-syntax-error (c) (format t "correctly errored: ~A~%" c))))

(format t "~%== the SEPARATE, real limitation Eduardo's 'and/or' question~%")
(format t "   was pointing at: a comparison CANNOT be combined with another~%")
(format t "   goal into a single TERM (as opposed to separate body goals)~%")
(format t "   for something like FINDALL's Goal argument -- this is a gap~%")
(format t "   in FINDALL/BAGOF/SETOF's own design (no ','/2 term operator~%")
(format t "   exists at all in this engine), identical whether the~%")
(format t "   comparison inside is spelled infix or prefix; NOT something~%")
(format t "   this change introduces or could fix by itself ==~%")
(<- (item a 1)) (<- (item b 2)) (<- (item c 3))
(format t "findall(?x, (item ?x ?n), ?xs) -- single goal, works fine: ")
(?- (findall ?x (item ?x ?n) ?xs))
(format t "(?- (findall ?x (and (item ?x ?n) (> ?n 1)) ?xs)) -- ~%")
(format t "  would need a real AND/2 (or ','/2) term operator that simply~%")
(format t "  doesn't exist yet; not attempted here, on purpose.~%")

(format t "~%All infix-comparison checks ran.~%")
(sb-ext:exit)
