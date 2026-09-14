;;; findall-bagof-setof-call-tests.lisp -- verification-only, 2026-09-14.
;;; Confirms the FINDALL/3, BAGOF/3, SETOF/3, CALL/N builtins already in
;;; prolog-engine.lisp (added earlier, motivated by pipeline.lisp's need to
;;; group/order SUBSTEP facts) actually work, including the one place their
;;; behavior deliberately falls short of ISO Prolog: BAGOF/SETOF here do NOT
;;; group solutions by the goal's own free variables -- see the "grouping
;;; gap" section below, which demonstrates that concretely rather than just
;;; asserting it.

(load "prolog-engine.lisp")

;; --- shared fact base ---------------------------------------------------
(<- (color apple red))
(<- (color cherry red))
(<- (color banana yellow))
(<- (color lemon yellow))
(<- (color grape purple))

(<- (parent tom bob))
(<- (parent tom liz))
(<- (parent bob ann))
(<- (parent bob pat))

(format t "~%== findall/3 ==~%")
(format t "findall red things: ")
(?- (findall ?x (color ?x red) ?l))
(format t "  (expect L = (APPLE CHERRY))~%")

(format t "findall of a nonexistent color (never fails, gives NIL): ")
(?- (findall ?x (color ?x teal) ?l))
(format t "  (expect L = NIL)~%")

(format t "~%== bagof/3, the case it's actually meant for: no free~%")
(format t "   variables in Goal beyond what's already bound ==~%")
(format t "bagof things bob is parent of: ")
(?- (bagof ?c (parent bob ?c) ?l))
(format t "  (expect L = (ANN PAT))~%")
(format t "bagof with a goal that has no solutions (must FAIL, not give NIL): ")
(?- (bagof ?c (parent nobody ?c) ?l))
(format t "  (expect no)~%")

(format t "~%== setof/3: bagof plus sort+dedupe ==~%")
(<- (likes mary wine))
(<- (likes mary food))
(<- (likes mary wine))  ; deliberate duplicate fact
(format t "setof what mary likes (sorted, deduped): ")
(?- (setof ?x (likes mary ?x) ?l))
(format t "  (expect L = (FOOD WINE) -- alphabetical, WINE listed once)~%")

(format t "~%== the grouping gap: BAGOF/SETOF here do NOT partition by~%")
(format t "   Goal's free variables the way ISO bagof/setof do ==~%")
(format t "Real ISO bagof(Child, parent(Parent,Child), L) with Parent left~%")
(format t "unbound backtracks over EACH Parent separately: Answer 1 would be~%")
(format t "Parent=tom, L=(bob liz); Answer 2 would be Parent=bob, L=(ann pat).~%")
(format t "This engine's bagof/setof instead lump every solution into ONE~%")
(format t "list regardless of Parent, and only ever produce one answer:~%")
(?-all (bagof ?c (parent ?p ?c) ?l))
(format t "  (actual: one answer, L = (BOB LIZ ANN PAT), ?P left unbound in~%")
(format t "   the template so its bindings during the sub-search are thrown~%")
(format t "   away -- exactly FINDALL's behavior, which is what BAGOF/SETOF~%")
(format t "   are actually built from here. Fine for every current caller,~%")
(format t "   which always binds every variable in Goal except Template's own~%")
(format t "   before calling BAGOF/SETOF -- wrong if a future caller relies~%")
(format t "   on real grouping.)~%")

(format t "~%== call/N ==~%")
(<- (double ?x ?y) (lisp-eval ?y (* ?x 2)))
(format t "call/2, plain predicate symbol as Goal: ")
(?- (call double 21 ?y))
(format t "  (expect Y = 42)~%")

(<- (add ?a ?b ?c) (lisp-eval ?c (+ ?a ?b)))
(format t "call/3 built from a partially-applied compound Goal, (add 10): ")
(?- (call (add 10) 5 ?c))
(format t "  (expect C = 15)~%")

(format t "~%== call/N cut-transparency: a ! inside the CALLED predicate's own~%")
(format t "   clause commits only that predicate's own choice, never reaching~%")
(format t "   back to cut a choice point that belongs to the CALLER ==~%")
(<- (pick 1) !)
(<- (pick 2))
(format t "call(pick, ?x) on backtracking (expect exactly ONE answer, X=1 --~%")
(format t " pick's own ! must fire the same way whether called directly or~%")
(format t " reached via call/N):~%")
(?-all (call pick ?x))

(<- (outer 1))
(<- (outer 2))
(<- (inner yes) !)
(<- (inner no))
(<- (combo ?o ?i) (outer ?o) (call inner ?i))
(format t "~%combo backtracking (outer has 2 clauses with no cut of its own;~%")
(format t "inner has a ! that must cut only INNER's alternatives, never~%")
(format t "OUTER's -- expect exactly TWO answers, O=1/I=YES then O=2/I=YES,~%")
(format t "never O=1/I=NO and never just one answer):~%")
(?-all (combo ?o ?i))

(format t "~%All findall/bagof/setof/call/N checks ran -- compare actual output~%")
(format t "above against each \"(expect ...)\" line.~%")
