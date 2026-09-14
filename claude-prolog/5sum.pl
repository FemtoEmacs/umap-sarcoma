% 5sum.pl -- Edinburgh-notation port of 5sum.lisp.
%
% count-up/4: like count-up/2 (1prolog-test.pl), but threads a SECOND
% accumulator S along for the ride, stepping it by 0.02 each time N
% steps by 0.01 -- a different arity (4, not 2) of the same functor
% name, a separate predicate from 1prolog-test.pl's count-up/2 even if
% both files are consulted into the same database.

% Rule 1: once we hit or pass the requested stop number, cut (!) and return.
count-up(N, Stop, S, S) :- N >= Stop, !.

% Rule 2: keep counting upward by 0.01 until the stop rule succeeds.
count-up(N, Stop, S, Out) :-
    Next is (+ N 0.01),
    S1 is (+ S 0.02),
    count-up(Next, Stop, S1, Out).

% Example: edinburgh-query("count-up(0, 100, 0, Result)")
