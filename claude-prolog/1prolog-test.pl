% 1prolog-test.pl -- Edinburgh-notation port of 1prolog-test.lisp.
% count-up(N, Out): count N upward by 0.01 until it reaches 10, then Out
% is bound to wherever it stopped.

% Rule 1: once we hit or pass 10, cut (!) and stop tracking further rules.
count-up(N, Out) :- N >= 10, !, Out = N.

% Rule 2: fallback processing rule.
count-up(N, Out) :- Next is (+ N 0.01), count-up(Next, Out).

% Example: consult("1prolog-test.pl"). then edinburgh-query("count-up(0, Result)").
