;; P-99 (Ninety-Nine Prolog Problems), problems 1-10.
;; https://www.ic.unicamp.br/~meidanis/courses/mc336/2009s2/prolog/problemas/
;;
;; All ten solved with only what claude-prolog already provides: unification,
;; multi-clause resolution with backtracking, cut (!), and lisp-eval/is for
;; arithmetic. No engine changes, no (callable ...) registrations needed.
;;
;; Convention used throughout: an empty list is `nil`, a nonempty list is
;; `(?head . ?tail)` -- ordinary Lisp cons cells, since that's what this
;; engine's terms are built from. Predicates are prefixed p01- .. p10- to
;; keep them distinct if multiple problem files ever get loaded together;
;; later problems freely reuse earlier ones' helper predicates (p04-count,
;; p05-reverse, p09-pack) rather than redefining them.
;;
;; Load with (load "prolog-engine.lisp") then (load "99/p01-p10.lisp").

;; --- P01 (*): last element of a list -------------------------------------
;; my_last(X,[a,b,c,d]) -> X = d
(<- (p01-last ?x (?x)) !)
(<- (p01-last ?x (?_ . ?xs)) ! (p01-last ?x ?xs))

;; --- P02 (*): last-but-one (second to last) element ----------------------
(<- (p02-last-but-one ?x (?x ?_)) !)
(<- (p02-last-but-one ?x (?_ . ?xs)) ! (p02-last-but-one ?x ?xs))

;; --- P03 (*): K'th element of a list, 1-indexed ---------------------------
;; element_at(X,[a,b,c,d,e],3) -> X = c
(<- (p03-element-at ?x (?x . ?_) 1) !)
(<- (p03-element-at ?x (?_ . ?xs) ?k)
    (lisp-eval t (> ?k 1))
    !
    (lisp-eval ?k1 (- ?k 1))
    (p03-element-at ?x ?xs ?k1))

;; --- P04 (*): count the elements of a list --------------------------------
(<- (p04-count nil 0) !)
(<- (p04-count (?_ . ?xs) ?n)
    !
    (p04-count ?xs ?n1)
    (lisp-eval ?n (+ ?n1 1)))

;; --- P05 (*): reverse a list -----------------------------------------------
;; Accumulator-based, so it's tail-recursive at the Prolog level too.
(<- (p05-reverse ?xs ?ys) (p05-reverse-acc ?xs nil ?ys))
(<- (p05-reverse-acc nil ?acc ?acc) !)
(<- (p05-reverse-acc (?h . ?t) ?acc ?ys) ! (p05-reverse-acc ?t (?h . ?acc) ?ys))

;; --- P06 (*): find out whether a list is a palindrome ---------------------
;; Classic idiom: L is a palindrome iff reversing L gives back L itself --
;; calling p05-reverse with the SAME variable in both list positions forces
;; that check via unification, no separate equality test needed.
(<- (p06-palindrome ?xs) (p05-reverse ?xs ?xs))

;; --- P07 (**): flatten a nested list structure ----------------------------
;; my_flatten([a,[b,[c,d],e]],X) -> X = [a,b,c,d,e]
;; The three cases (nil / cons / atomic) are mutually structurally exclusive
;; via unification alone -- cut just discards the choice points that would
;; otherwise linger for backtracking purposes (see NOTES.md on this idiom).
(<- (p07-flatten nil nil) !)
(<- (p07-flatten (?h . ?t) ?flat)
    !
    (p07-flatten ?h ?flat-h)
    (p07-flatten ?t ?flat-t)
    (p07-append ?flat-h ?flat-t ?flat))
(<- (p07-flatten ?x (?x)))

(<- (p07-append nil ?ys ?ys) !)
(<- (p07-append (?h . ?xs) ?ys (?h . ?zs)) ! (p07-append ?xs ?ys ?zs))

;; --- P08 (**): eliminate consecutive duplicates ---------------------------
;; compress([a,a,a,a,b,c,c,a,a,d,e,e,e,e],X) -> X = [a,b,c,a,d,e]
;; The "same element repeated" clause uses the SAME variable ?x twice in
;; its head, so unification itself enforces equality of the first two list
;; elements -- no \== builtin needed. The cut there discards the otherwise-
;; live "treat them as different" alternative for that case.
(<- (p08-compress nil nil) !)
(<- (p08-compress (?x) (?x)) !)
(<- (p08-compress (?x ?x . ?xs) ?ys) ! (p08-compress (?x . ?xs) ?ys))
(<- (p08-compress (?x ?y . ?xs) (?x . ?ys)) ! (p08-compress (?y . ?xs) ?ys))

;; --- P09 (**): pack consecutive duplicates into sublists ------------------
;; pack([a,a,a,a,b,c,c,a,a,d,e,e,e,e],X)
;;   -> X = [[a,a,a,a],[b],[c,c],[a,a],[d],[e,e,e,e]]
(<- (p09-pack nil nil) !)
(<- (p09-pack (?x . ?xs) (?run . ?zs))
    !
    (p09-transfer ?x ?xs ?ys ?run)
    (p09-pack ?ys ?zs))

;; p09-transfer(X, Rest, Remaining, Run): peel off a run of X's from the
;; front of [X|Rest], returning the run and what's left over.
(<- (p09-transfer ?x nil nil (?x)) !)
(<- (p09-transfer ?x (?x . ?xs) ?ys (?x . ?run)) ! (p09-transfer ?x ?xs ?ys ?run))
(<- (p09-transfer ?x (?y . ?ys) (?y . ?ys) (?x)))

;; --- P10 (*): run-length encoding ------------------------------------------
;; encode([a,a,a,a,b,c,c,a,a,d,e,e,e,e],X)
;;   -> X = [[4,a],[1,b],[2,c],[2,a],[1,d],[4,e]]
(<- (p10-encode ?list ?encoded)
    (p09-pack ?list ?packed)
    (p10-encode-runs ?packed ?encoded))

(<- (p10-encode-runs nil nil) !)
(<- (p10-encode-runs (?run . ?runs) ((?n ?x) . ?rest))
    !
    (p10-run-info ?run ?n ?x)
    (p10-encode-runs ?runs ?rest))

(<- (p10-run-info (?x . ?xs) ?n ?x) (p04-count (?x . ?xs) ?n))
