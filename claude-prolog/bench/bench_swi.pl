:- set_prolog_flag(double_quotes, codes).

% ---------- Benchmark 1: tail-recursive arithmetic loop ----------
% Same predicate as claude-prolog's count-up3, same step count (1,000,000).
count_up3(N,Stop,Out) :- N >= Stop, !, Out = N.
count_up3(N,Stop,Out) :- Next is N+0.01, count_up3(Next,Stop,Out).

% ---------- Benchmark 2: naive reverse, repeated ----------
myapp([],Ys,Ys).
myapp([X|Xs],Ys,[X|Zs]) :- myapp(Xs,Ys,Zs).

nrev([],[]).
nrev([X|Xs],Ys) :- nrev(Xs,Zs), myapp(Zs,[X],Ys).

mklist(0,[]) :- !.
mklist(N,[N|T]) :- N>0, N1 is N-1, mklist(N1,T).

repeat_nrev(0,_) :- !.
repeat_nrev(K,List) :- K > 0, !, nrev(List,_), K1 is K-1, repeat_nrev(K1,List).

% ---------- Benchmark 3: 8-queens, count all solutions ----------
% Same generate-a-permutation-then-test-safety algorithm on both sides
% (not SWI's builtin permutation/2 or library(clpfd) -- hand-rolled to
% keep the algorithm identical across implementations).
my_select(X,[X|Xs],Xs).
my_select(X,[Y|Ys],[Y|Zs]) :- my_select(X,Ys,Zs).

my_permute([],[]).
my_permute(L,[X|Xs]) :- my_select(X,L,Rest), my_permute(Rest,Xs).

my_numlist(Lo,Hi,[]) :- Lo > Hi, !.
my_numlist(Lo,Hi,[Lo|T]) :- Lo =< Hi, !, Lo1 is Lo+1, my_numlist(Lo1,Hi,T).

safe([]).
safe([Q|Qs]) :- safe(Qs,Q,1), safe(Qs).
safe([],_,_).
safe([Q|Qs],Q0,D0) :-
    Q0 =\= Q+D0, Q0 =\= Q-D0,
    D1 is D0+1,
    safe(Qs,Q0,D1).

queens(N,Qs) :- my_numlist(1,N,Ns), my_permute(Ns,Qs), safe(Qs).

count_queens(N,Count) :- aggregate_all(count, queens(N,_), Count).

run :-
    format("~n== Benchmark 1: count_up3(0,10000,X), 1,000,000 tail-recursive steps ==~n"),
    get_time(T0a), count_up3(0,10000,X), get_time(T1a),
    Dt1 is T1a - T0a,
    format("result X=~w  wall=~4f s~n", [X, Dt1]),
    time(count_up3(0,10000,_)),

    format("~n== Benchmark 2: 200 reps of nrev/2 on a 100-element list ==~n"),
    mklist(100, List),
    get_time(T0b), repeat_nrev(200, List), get_time(T1b),
    Dt2 is T1b - T0b,
    format("wall=~4f s~n", [Dt2]),
    time(repeat_nrev(200, List)),

    format("~n== Benchmark 2b: nrev size scaling (doubling L, single call each) ==~n"),
    forall(member(N,[10,20,40,80,160,320,640,1280]),
           ( mklist(N,L2),
             get_time(T0d), nrev(L2,_), get_time(T1d),
             Dt4 is T1d-T0d,
             format("L=~w: ~4f s~n",[N,Dt4]) )),

    format("~n== Benchmark 3: 8-queens, count all solutions (expect 92) ==~n"),
    get_time(T0c), count_queens(8, N), get_time(T1c),
    Dt3 is T1c - T0c,
    format("solutions=~w  wall=~4f s~n", [N, Dt3]),
    time(count_queens(8,_)).

:- run, halt.
