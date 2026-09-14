% family.pl -- a small example file in Edinburgh notation, meant to be
% loaded with (consult-edinburgh-file "family.pl") once prolog-engine.lisp
% and edinburgh-reader.lisp are both loaded. See NOTES.md for the syntax
% rules (no infix operators anywhere -- arithmetic/comparisons are always
% written as ordinary compound terms or bare Lisp forms, never as X is Y).

parent(tom, bob).
parent(tom, liz).
parent(bob, ann).
parent(bob, pat).
parent(pat, jim).

grandparent(X, Y) :- parent(X, Z), parent(Z, Y).

age(tom, 70).
age(bob, 45).
age(liz, 42).
age(ann, 19).

older(X, Y) :- age(X, AgeX), age(Y, AgeY), AgeX > AgeY.

% A directive: runs immediately, the moment the file reaches this line
% during consult -- not deferred to some later "run all directives" pass.
% (FORMAT has to be registered from the Lisp side first with
% (register-callable 'format) -- lisp-eval can't register its own
% functions from inside a directive, deliberately: that would let any
% Prolog source file grant itself access to arbitrary Lisp functions.)
:- (lisp-eval t (format t "family.pl consulted -- ~D grandparent facts derivable~%" 4)).
