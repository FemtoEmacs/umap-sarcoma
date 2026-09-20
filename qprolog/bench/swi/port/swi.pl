% port/swi.pl -- SWI-Prolog glue for run.pl
:- use_module(library(lists)).
:- use_module(library(apply)).
get_performance_stats(GC, Time) :-
    statistics(cputime, Time),
    statistics(garbage_collection, [_,_,GCms|_]),
    GC is GCms/1000.0.
no_singletons :- style_check(-singleton).
system_satisfies(ssu) :- !, catch(atom_to_term('a(_) => true', _, _), _, fail).
system_satisfies(_).
