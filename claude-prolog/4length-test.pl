% 4length-test.pl -- Edinburgh-notation port of 4length-test.lisp.
%
% Deterministic list length relation.
% list-len(Xs, N) means: N is the number of elements in the proper list Xs.

% Base case: the empty list has length 0.
list-len([], 0).

% Recursive case: if Tail has length TailN, then [Head|Tail] has length
% TailN + 1.
list-len([Head|Tail], N) :- list-len(Tail, TailN), N is (+ TailN 1).

% Examples:
%   edinburgh-query("list-len([], N)")           => N = 0
%   edinburgh-query("list-len([a,b,c,d], N)")    => N = 4
