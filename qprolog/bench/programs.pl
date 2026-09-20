% programs.pl -- iteration counts for run.pl (bench/swi).
% Counts are the upstream SWI-Prolog `bench/programs.pl` values (each is
% calibrated to take about a second in SWI-Prolog); names follow the file
% names in this directory (serialise -> serialize, derive = ops8+log10+
% divide10 in one program).
:- dynamic result/3.

program(boyer,           47).
program(browse,          32).
program(chat_parser,    128).
program(crypt,         3480).
program(derive,      279547).
program(det,            169).
program(divide10,    698324).
program(fast_mu,      17354).
program(reducer,        567).
program(sendmore,       127).
program(serialize,    53129).
program(sieve,          56).
program(simple_analyzer,1144).
program(tak,            128).
program(zebra,          576).

program_condition(det, ssu).
