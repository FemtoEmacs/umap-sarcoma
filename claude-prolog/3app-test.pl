% 3app-test.pl -- Edinburgh-notation port of 3app-test.lisp.
%
% Non-deterministic append relation.
% app(Xs, Ys, Zs) means: list Zs is the result of appending list Xs to
% list Ys.

% Base case: appending the empty list to Ys gives Ys.
app([], Ys, Ys).

% Recursive case: if appending Xs to Ys gives Zs, then appending [H|Xs]
% to Ys gives [H|Zs].
app([H|Xs], Ys, [H|Zs]) :- app(Xs, Ys, Zs).

% Examples:
%
% Forward append:
%   edinburgh-query("app([1,2], [3,4], Result)")
%   => Result = (1 2 3 4)
%
% Relational / non-deterministic split (backtrack with ?-all):
%   (?-all (app ?left ?right (1 2 3)))
%   first answer:  Left = [],      Right = [1,2,3]
%   other answers: Left = [1],     Right = [2,3]
%                  Left = [1,2],   Right = [3]
%                  Left = [1,2,3], Right = []
