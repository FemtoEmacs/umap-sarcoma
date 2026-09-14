;;; edinburgh-read-macro-tests.lisp -- verification for edinburgh-read-
;;; macro.lisp: the embedded '?-pred(...);' query syntax itself, and --
;;; just as important -- proof that turning it on doesn't disturb a
;;; single existing convention (?x pvars, (?- (goal)), (?-all (goal))).
;;; Run with: sbcl --script edinburgh-read-macro-tests.lisp

(load "edinburgh-read-macro.lisp")
(consult "3app-test.pl")
(consult "99-p01-p10.pl")

(format t "~%== before enabling: '?-app(...);' is NOT special yet (plain~%")
(format t "   reader has no idea what to do with 'app(' tight after '?-',~%")
(format t "   so this section runs entirely on the STANDARD readtable) ==~%")
(format t "?- (app (1 2) (3 4) ?z)) via ordinary bracket syntax, unaffected: ")
(?- (app (1 2) (3 4) ?z))

(enable-edinburgh-syntax)

(format t "~%== enabled: the user's exact example ==~%")
?-app(Left, Right, [3,4.5]);
(format t "  (expect Left = NIL, Right = (3 4.5))~%")

(format t "~%== multiple comma-separated goals in one embedded query ==~%")
?-p04-count([a,b,c,d], N), p01-last(X, [a,b,c,d]);
(format t "  (expect N = 4, X = D)~%")

(format t "~%== a comment can immediately follow the terminating ';' --~%")
(format t "   ';' itself was never redefined, only scanned for raw ==~%")
?-p05-reverse([a,b,c], Ys); ; ordinary Lisp comment, unaffected
(format t "  (expect Ys = (C B A))~%")

(format t "~%== critical regression check: ordinary '?x' pvars, and the~%")
(format t "   existing bracket-syntax (?- ...)/(?-all ...) macros, are~%")
(format t "   UNCHANGED now that '?' is a reader macro character ==~%")
(format t "a bare pvar symbol, ?foo: ~S (expect |?FOO|)~%" '?foo)
(format t "the anonymous-var-style symbol _: ~S (expect _)~%" '_)
(format t "ordinary bracket query, (?- (app (1 2) (3 4) ?z)): ")
(?- (app (1 2) (3 4) ?z))
(format t "ordinary bracket backtracking, (?-all (app ?l ?r (1 2 3))):~%")
(?-all (app ?l ?r (1 2 3)))

(format t "~%== '?-someatom' with nothing tight-paren-following at all --~%")
(format t "   still just the plain symbol ?-SOMEATOM, unaffected ==~%")
(format t "~S (expect |?-SOMEATOM|)~%" '?-someatom)

(format t "~%== a malformed embedded query (no closing ';') is a clear~%")
(format t "   Lisp-level error, not a hang or a silent misread ==~%")
(handler-case
    (progn (read-from-string "?-p01-last(X, [a,b,c])")
           (format t "SHOULD HAVE ERRORED~%"))
  (error (c) (format t "correctly errored: ~A~%" c)))

(disable-edinburgh-syntax)
(format t "~%== disabled again: back to the plain standard readtable ==~%")
(format t "~S (expect |?-APP|, since app( is no longer special)~%" (read-from-string "?-app"))

(format t "~%All read-macro checks ran.~%")
(sb-ext:exit)
