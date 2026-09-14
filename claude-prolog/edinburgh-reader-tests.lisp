;;; edinburgh-reader-tests.lisp -- verification for edinburgh-reader.lisp,
;;; 2026-09-14. Covers the term grammar, the goal-level rewrites, clause/
;;; directive installation and interop with the bracket syntax, and --
;;; per "error detection, of course" -- a battery of malformed input,
;;; checking each one is a CLEAR reported error (not a crash, and not a
;;; silent wrong parse), and that the file-level consult loop resyncs
;;; past one bad clause and keeps reading the rest.

(load "prolog-engine.lisp")
(load "edinburgh-reader.lisp")

(defmacro expect (form expected)
  `(let ((actual ,form))
     (format t "~&~A => ~S ~:[MISMATCH, expected ~S~;ok~]~%"
             ',form actual (equal actual ,expected) ,expected)))

(format t "~%== atoms, variables, numbers, strings ==~%")
(expect (edinburgh-term "apple") (intern "APPLE"))
(expect (edinburgh-term "'Apple'") (intern "Apple"))
(expect (edinburgh-term "X") (intern "?X"))
(expect (edinburgh-term "_Foo") (intern "?_Foo"))
(expect (edinburgh-term "_") (intern "_"))
(expect (edinburgh-term "42") 42)
(expect (edinburgh-term "3.14") 3.14)
(expect (edinburgh-term "-5") -5)
(expect (edinburgh-term "-5.5") -5.5)
(expect (edinburgh-term "\"hi\\nthere\"") (format nil "hi~%there"))

(format t "~%== compound terms and the two parenthesis forms ==~%")
(expect (edinburgh-term "foo(a, b, c)") (list (intern "FOO") (intern "A") (intern "B") (intern "C")))
(expect (edinburgh-term "+(X, 1)") (list (intern "+") (intern "?X") 1))
(expect (edinburgh-term "(+ X 1)") (list (intern "+") (intern "?X") 1))
(expect (edinburgh-term "(+ (* 2 3) 1)") (list (intern "+") (list (intern "*") 2 3) 1))
(expect (edinburgh-term "!") (intern "!"))

(format t "~%== lists ==~%")
(expect (edinburgh-term "[]") nil)
(expect (edinburgh-term "[a, b, c]") (list (intern "A") (intern "B") (intern "C")))
(expect (edinburgh-term "[H|T]") (cons (intern "?H") (intern "?T")))
(expect (edinburgh-term "[a, b|T]") (list* (intern "A") (intern "B") (intern "?T")))

(format t "~%== comments are invisible to the reader ==~%")
(expect (edinburgh-term "foo(a, % a trailing comment
                          b)") (list (intern "FOO") (intern "A") (intern "B")))
(expect (edinburgh-term "/* a block\n comment */ foo") (intern "FOO"))

(format t "~%== negative-number resolution needs no special rule (see file banner) ==~%")
(expect (edinburgh-term "-(5)") (list (intern "-") 5))
(handler-case (progn (edinburgh-term "3 - 1") (format t "SHOULD HAVE ERRORED on '3 - 1'~%"))
  (edinburgh-syntax-error (c) (format t "'3 - 1' correctly rejected: ~A~%" c)))

(format t "~%== clauses, rules, facts, interop with the bracket syntax ==~%")
(consult-edinburgh-string "
color(apple, red).
color(cherry, red).
color(banana, yellow).
parent(tom, bob).
")
;; a bracket-syntax fact, into the SAME database, same predicate:
(<- (color grape purple))
(format t "findall of red things via bracket-syntax findall, over Edinburgh-asserted facts: ")
(?- (findall ?x (color ?x red) ?l))
(format t "  (expect L = (APPLE CHERRY))~%")
(format t "color(grape, ?c) -- asserted via bracket syntax, queried via Edinburgh: ")
(edinburgh-query "color(grape, C)")
(format t "  (expect C = PURPLE)~%")

(format t "~%== rules, cut, recursion -- note IS and the comparators lose~%")
(format t "   their infix look too, same as +/-/*: no operators survive at~%")
(format t "   all, so is(Y, Expr)/>(N,0) replace 'Y is Expr'/'N > 0' ==~%")
(consult-edinburgh-string "
double(X, Y) :- is(Y, (* X 2)).
countdown(0) :- !.
countdown(N) :- >(N, 0), is(N1, (- N 1)), countdown(N1).
")
(format t "double(21, ?y): ")
(edinburgh-query "double(21, Y)")
(format t "  (expect Y = 42)~%")
(format t "countdown(3) (expect: succeeds, exactly once via the cut): ")
(?-all (countdown 3))

(format t "~%== = means unification, not this engine's internal numeric = ==~%")
(consult-edinburgh-string "unifies_ok(X) :- =(X, foo(bar, 1)).")
(format t "unifies_ok(?r), expect R = FOO(BAR,1), not a Lisp type error: ")
(edinburgh-query "unifies_ok(R)")

(format t "~%== comparator spelling table (=:=, =\\=, =<, and plain <, >, >=) ==~%")
(consult-edinburgh-string "
cmp_test(1) :- =:=(5, (+ 2 3)).
cmp_test(2) :- =\\=(5, 6).
cmp_test(3) :- =<(3, 3).
cmp_test(4) :- <(3, (+ 1 3)).
cmp_test(5) :- >((+ 2 2), 3).
cmp_test(6) :- >=(4, 4).
")
(dotimes (i 6)
  (format t "cmp_test(~D): " (1+ i))
  (edinburgh-query (format nil "cmp_test(~D)" (1+ i))))

(format t "~%== directives run immediately, at consult time ==~%")
;; FORMAT isn't on lisp-eval's default whitelist (a real, deliberate
;; engine restriction, unrelated to this reader -- confirmed separately);
;; REGISTER-CALLABLE is the engine's own documented extension mechanism
;; for exactly this, same for either front end, so use it here rather
;; than work around the restriction.
(register-callable 'format)
(consult-edinburgh-string ":- (lisp-eval t (format t \"directive ran during consult, printed while consulting~%\")).")

(format t "~%== not-yet-implemented comparators fail cleanly, not crash ==~%")
(consult-edinburgh-string "never_true(X, Y) :- \\=(X, Y).")
(format t "never_true(a, b) (expect no -- \\= isn't implemented, same known gap as \\+): ")
(edinburgh-query "never_true(a, b)")

(format t "~%== error detection: each of these must be a clear, position-tagged~%")
(format t "   syntax error -- never a crash, never a silent wrong parse ==~%")
(dolist (bad (list "'unterminated atom"
                    "\"unterminated string"
                    "/* unterminated comment"
                    "foo(a, b"
                    "foo()"
                    "()"
                    "foo(a,, b)"
                    "[a, b"
                    "foo(a) bar(b)"
                    "X \\q Y"))
  (handler-case (progn (edinburgh-term bad) (format t "~S: SHOULD HAVE ERRORED~%" bad))
    (edinburgh-syntax-error (c) (format t "~S:~%  -> ~A~%" bad c))))

(format t "~%== a clause missing its terminator at EOF ==~%")
;; CONSULT-EDINBURGH-STRING never signals -- by design (see the resync
;; section below) it catches its own syntax errors so one bad clause
;; can't abort a whole file load, reporting them back as its second
;; return value instead. So this checks THAT, not a thrown condition.
(multiple-value-bind (installed errors) (consult-edinburgh-string "foo(a, b) :- bar(a)")
  (format t "installed: ~D (expect 0), errors: ~D (expect 1)~%" installed (length errors))
  (if (= (length errors) 1)
      (format t "  -> ~A~%" (first errors))
      (format t "SHOULD HAVE REPORTED EXACTLY ONE ERROR~%")))

(format t "~%== multi-error resync: three clauses, the middle one broken, both~%")
(format t "   good ones still install and the broken one is reported once ==~%")
(multiple-value-bind (installed errors)
    (consult-edinburgh-string "
good1(ok).
bad1 :- .
good2(ok).
")
  (format t "installed: ~D (expect 2), errors reported: ~D (expect 1)~%" installed (length errors))
  (format t "good1(?x): ") (edinburgh-query "good1(X)")
  (format t "good2(?x): ") (edinburgh-query "good2(X)"))

(format t "~%All edinburgh-reader checks ran.~%")
(sb-ext:exit)
