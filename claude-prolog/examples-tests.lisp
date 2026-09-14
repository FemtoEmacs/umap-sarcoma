;;; examples-tests.lisp -- consults every Edinburgh-notation example file
;;; and checks its results against the expectations documented in the
;;; original bracket-syntax source each one was ported from.
;;; RUN-QUERY returns a plain list of the query's named variables' ground
;;; values (in first-occurrence order), or NIL on failure -- exact enough
;;; to CHECK against directly for the integer/symbol/list results below;
;;; the floating-point count-up/count-up3/5sum queries are run via ?- and
;;; eyeballed instead (see each file's own header comment for why: 1000
;;; steps of adding 0.01 has no reason to land on an exact printable value).
;;; Run with: sbcl --script examples-tests.lisp

(load "prolog-engine.lisp")
(load "edinburgh-reader.lisp")

(defmacro check (form expected)
  `(let ((actual ,form))
     (format t "~&~A => ~S ~:[MISMATCH, expected ~S~;ok~]~%"
             ',form actual (equal actual ,expected) ,expected)))

(format t "== 1prolog-test.pl: count-up/2 ==~%")
(consult "1prolog-test.pl")
(format t "count-up(0, Out): ") (?- (count-up 0 ?out))
(format t "  (expect Out close to 10)~%")

(format t "~%== 2prolog-test.pl: count-up3/3 ==~%")
(consult "2prolog-test.pl")
(format t "count-up3(0, 100, Out): ") (?- (count-up3 0 100 ?out))
(format t "  (expect Out close to 100)~%")

(format t "~%== 3app-test.pl: app/3 ==~%")
(consult "3app-test.pl")
(check (run-query '(app (1 2) (3 4) ?result)) '((1 2 3 4)))
(format t "non-deterministic split, every answer:~%")
(?-all (app ?left ?right (1 2 3)))

(format t "~%== 4length-test.pl: list-len/2 ==~%")
(consult "4length-test.pl")
(check (run-query '(list-len nil ?n)) '(0))
(check (run-query '(list-len (a b c d) ?n)) '(4))

(format t "~%== 5sum.pl: count-up/4 (different arity, same functor as #1) ==~%")
(consult "5sum.pl")
(format t "count-up(0, 100, 0, Result): ") (?- (count-up 0 100 0 ?result))
(format t "  (expect Result close to 200 -- S steps by 0.02 while N, the~%")
(format t "   thing actually compared against Stop=100, steps by 0.01)~%")

(format t "~%== 99-p01-p10.pl: P-99 problems 1-10 -- also a hyphenated-atom~%")
(format t "   workout for ordinary (non-Lisp-escape) Prolog syntax ==~%")
(consult "99-p01-p10.pl")

(check (run-query '(p01-last ?x (a b c d))) '(d))
(check (run-query '(p02-last-but-one ?x (a b c d))) '(c))
(check (run-query '(p03-element-at ?x (a b c d e) 3)) '(c))
(check (run-query '(p04-count (a b c d) ?n)) '(4))
(check (run-query '(p05-reverse (a b c d) ?ys)) '((d c b a)))
(format t "p06-palindrome((a b c b a)): ") (?- (p06-palindrome (a b c b a)))
(format t "  (expect yes)~%")
(format t "p06-palindrome((a b c d)): ") (?- (p06-palindrome (a b c d)))
(format t "  (expect no)~%")
(check (run-query '(p07-flatten (a (b (c d) e)) ?x)) '((a b c d e)))
(check (run-query '(p08-compress (a a a a b c c a a d e e e e) ?ys))
       '((a b c a d e)))
(check (run-query '(p09-pack (a a a a b c c a a d e e e e) ?zs))
       '(((a a a a) (b) (c c) (a a) (d) (e e e e))))
(check (run-query '(p10-encode (a a a a b c c a a d e e e e) ?encoded))
       '(((4 a) (1 b) (2 c) (2 a) (1 d) (4 e))))

(format t "~%All example-file checks ran.~%")
(sb-ext:exit)
