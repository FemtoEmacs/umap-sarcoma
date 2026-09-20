% swi-bench.pl -- entry point for the SWI baseline:  swipl -q swi-bench.pl -g 'run(1.0,csv)' -t halt
:- multifile user:file_search_path/2.
:- dynamic   user:file_search_path/2.
:- prolog_load_context(directory, D), assertz(user:file_search_path(bench, D)).
:- consult(run).
