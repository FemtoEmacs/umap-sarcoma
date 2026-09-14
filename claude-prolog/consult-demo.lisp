;;; consult-demo.lisp -- shows the actual thing Eduardo asked for: a plain
;;; (consult "family.pl") that loads a real .pl file written in Edinburgh
;;; notation and leaves it ready to query from Lisp, no ceremony.
;;; Run with: sbcl --script consult-demo.lisp

(load "prolog-engine.lisp")
(load "edinburgh-reader.lisp")

;; FORMAT isn't on lisp-eval's default whitelist (a deliberate engine
;; restriction -- see NOTES.md); family.pl's own directive uses it, so
;; register it here, from the Lisp side, before consulting the file.
(register-callable 'format)

(consult "family.pl")
(format t "~%")

(format t "Who are tom's grandchildren? ")
(?- (findall ?x (grandparent tom ?x) ?l))
(format t "  (expect (ANN PAT))~%~%")

(format t "Is bob older than liz? ")
(edinburgh-query "older(bob, liz)")
(format t "  (expect yes -- bob is 45, liz is 42)~%~%")

(format t "All grandparent/grandchild pairs, backtracking through every answer:~%")
(?-all (grandparent ?g ?c))

(sb-ext:exit)
