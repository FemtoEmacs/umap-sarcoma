% 99-p01-p10.pl -- Edinburgh-notation port of 99/p01-p10.lisp.
% P-99 (Ninety-Nine Prolog Problems), problems 1-10.
% https://www.ic.unicamp.br/~meidanis/courses/mc336/2009s2/prolog/problemas/
%
% All ten solved with only what claude-prolog already provides:
% unification, multi-clause resolution with backtracking, cut (!), and
% is/2 (lisp-eval underneath) for arithmetic. No engine changes needed.
%
% Predicates are prefixed p01- .. p10- to keep them distinct if multiple
% problem files ever get loaded together; later problems freely reuse
% earlier ones' helper predicates (p04-count, p05-reverse, p09-pack)
% rather than redefining them. This file is also, incidentally, a real
% workout for hyphenated atom names in ordinary (non-Lisp-escape) Prolog
% syntax -- ten predicates, every one of them hyphenated.

% --- P01 (*): last element of a list -------------------------------------
% p01-last(X, [a,b,c,d]) -> X = d
p01-last(X, [X]) :- !.
p01-last(X, [_|Xs]) :- !, p01-last(X, Xs).

% --- P02 (*): last-but-one (second to last) element ----------------------
p02-last-but-one(X, [X, _]) :- !.
p02-last-but-one(X, [_|Xs]) :- !, p02-last-but-one(X, Xs).

% --- P03 (*): K'th element of a list, 1-indexed ---------------------------
% p03-element-at(X, [a,b,c,d,e], 3) -> X = c
p03-element-at(X, [X|_], 1) :- !.
p03-element-at(X, [_|Xs], K) :-
    K > 1, !,
    K1 is (- K 1),
    p03-element-at(X, Xs, K1).

% --- P04 (*): count the elements of a list --------------------------------
p04-count([], 0) :- !.
p04-count([_|Xs], N) :- !, p04-count(Xs, N1), N is (+ N1 1).

% --- P05 (*): reverse a list -----------------------------------------------
% Accumulator-based, so it's tail-recursive at the Prolog level too.
p05-reverse(Xs, Ys) :- p05-reverse-acc(Xs, [], Ys).
p05-reverse-acc([], Acc, Acc) :- !.
p05-reverse-acc([H|T], Acc, Ys) :- !, p05-reverse-acc(T, [H|Acc], Ys).

% --- P06 (*): find out whether a list is a palindrome ---------------------
% Classic idiom: L is a palindrome iff reversing L gives back L itself --
% calling p05-reverse with the SAME variable in both list positions forces
% that check via unification, no separate equality test needed.
p06-palindrome(Xs) :- p05-reverse(Xs, Xs).

% --- P07 (**): flatten a nested list structure ----------------------------
% p07-flatten([a,[b,[c,d],e]], X) -> X = [a,b,c,d,e]
% The three cases (empty / cons / atomic) are mutually structurally
% exclusive via unification alone -- cut just discards the choice points
% that would otherwise linger for backtracking purposes.
p07-flatten([], []) :- !.
p07-flatten([H|T], Flat) :-
    !,
    p07-flatten(H, FlatH),
    p07-flatten(T, FlatT),
    p07-append(FlatH, FlatT, Flat).
p07-flatten(X, [X]).

p07-append([], Ys, Ys) :- !.
p07-append([H|Xs], Ys, [H|Zs]) :- !, p07-append(Xs, Ys, Zs).

% --- P08 (**): eliminate consecutive duplicates ---------------------------
% p08-compress([a,a,a,a,b,c,c,a,a,d,e,e,e,e], X) -> X = [a,b,c,a,d,e]
% The "same element repeated" clause uses the SAME variable X twice in
% its head, so unification itself enforces equality of the first two list
% elements -- no \== builtin needed. The cut there discards the otherwise-
% live "treat them as different" alternative for that case.
p08-compress([], []) :- !.
p08-compress([X], [X]) :- !.
p08-compress([X, X|Xs], Ys) :- !, p08-compress([X|Xs], Ys).
p08-compress([X, Y|Xs], [X|Ys]) :- !, p08-compress([Y|Xs], Ys).

% --- P09 (**): pack consecutive duplicates into sublists ------------------
% p09-pack([a,a,a,a,b,c,c,a,a,d,e,e,e,e], X)
%   -> X = [[a,a,a,a],[b],[c,c],[a,a],[d],[e,e,e,e]]
p09-pack([], []) :- !.
p09-pack([X|Xs], [Run|Zs]) :- !, p09-transfer(X, Xs, Ys, Run), p09-pack(Ys, Zs).

% p09-transfer(X, Rest, Remaining, Run): peel off a run of X's from the
% front of [X|Rest], returning the run and what's left over.
p09-transfer(X, [], [], [X]) :- !.
p09-transfer(X, [X|Xs], Ys, [X|Run]) :- !, p09-transfer(X, Xs, Ys, Run).
p09-transfer(X, [Y|Ys], [Y|Ys], [X]).

% --- P10 (*): run-length encoding ------------------------------------------
% p10-encode([a,a,a,a,b,c,c,a,a,d,e,e,e,e], X)
%   -> X = [[4,a],[1,b],[2,c],[2,a],[1,d],[4,e]]
p10-encode(List, Encoded) :- p09-pack(List, Packed), p10-encode-runs(Packed, Encoded).

p10-encode-runs([], []) :- !.
p10-encode-runs([Run|Runs], [[N, X]|Rest]) :-
    !,
    p10-run-info(Run, N, X),
    p10-encode-runs(Runs, Rest).

p10-run-info([X|Xs], N, X) :- p04-count([X|Xs], N).
