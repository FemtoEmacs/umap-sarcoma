% 2prolog-test.pl -- Edinburgh-notation port of 2prolog-test.lisp.
% count-up3(N, Stop, Out): like count-up/2, but the stop value is a
% parameter instead of a hardcoded 10.

% Rule 1: once we hit or pass the requested stop number, cut (!) and return.
count-up3(N, Stop, Out) :- N >= Stop, !, Out = N.

% Rule 2: keep counting upward by 0.01 until the stop rule succeeds.
count-up3(N, Stop, Out) :- Next is (+ N 0.01), count-up3(Next, Stop, Out).

% Example: edinburgh-query("count-up3(0, 100, Result)").
