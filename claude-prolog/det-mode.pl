% det-mode.pl -- Edinburgh-notation port of det-mode.lisp's five predicates
% (count-up/3, parity/2, minmax/4, firstof/2, append/3). This file only
% defines PLAIN clauses -- Edinburgh notation has no surface syntax for
% the +/- inline mode annotation det-mode.lisp uses on APPEND's head
% (+x . +xs)/(-x . -z), and couldn't: a bare '+' or '-' immediately
% before an atom is a symbolic-atom token in this grammar, not a mode
% marker, and even if it parsed, CONSULT installs clauses via ADD-CLAUSE
% directly, never through the redefined <- macro the inline-annotation
% detection hooks into (see NOTES.md).
%
% None of that is needed here, though: MODE's own compiler
% (COMPILE-DET-PREDICATE) reads whatever clauses are already sitting in
% the database and reconstructs each argument position's structure from
% the plain pattern plus the direction MODE was given -- it never looks
% for +/- markers on the stored clause itself (those get stripped down to
% ordinary ?-variables by STRIP-MODED-HEAD before the clause is ever
% asserted, inline-annotated or not). So: consult this file for the plain
% clauses, then declare each MODE explicitly, from the Lisp side, exactly
% once -- see det-mode-demo.lisp.

% --- 1. count-up: arithmetic only, no lists at all. ------------------------
count-up(N, Stop, Out) :- N >= Stop, !, Out = N.
count-up(N, Stop, Out) :- Next is (+ N 1), count-up(Next, Stop, Out).

% --- 2. parity: a fixed/literal output. ------------------------------------
parity(0, even) :- !.
parity(N, odd) :- N =:= 1, !.

% --- 3. minmax: two outputs at once, still plain arithmetic underneath. ----
minmax(A, B, Lo, Hi) :- A =< B, !, Lo = A, Hi = B.
minmax(A, B, Lo, Hi) :- Lo = B, Hi = A.

% --- 4. firstof: destructures a list via head cons-pattern matching only. -
firstof([X|Xs], X) :- !.

% --- 5. append: the compound-pattern example -- destructures its first
%    list AND builds its output list purely through cons patterns in the
%    clause heads. No lisp-eval anywhere in this predicate at all.
append([], Y, Y).
append([X|Xs], Y, [X|Z]) :- append(Xs, Y, Z).
