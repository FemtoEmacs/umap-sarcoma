# qprolog — a WAM-inspired Prolog engine in Common Lisp (SBCL)

qprolog is a Prolog engine written in Lisp. It keeps the *Lispy* bracket syntax of the earlier
`lispy-prolog` (a Prolog term is a Lisp list), but replaces the term-walking interpreter with a compiler in
the CxProlog/WAM tradition:

* clauses are **compiled** (through SBCL's `compile`) into machine-like code, split into WAM *chunks* at every call;
* control state (environment frames and choice points) lives in **preallocated arrays**, the trail is an array
  too, and registers are `sb-ext:defglobal`s;
* the other WAM features are there: first-argument indexing, last-call optimisation, cut via saved
  choice-point registers, conditional trailing, temporaries in registers (Lisp locals), permanent variables in
  the environment frame;
* **SBCL's garbage collector is kept**: terms are ordinary Lisp objects (atoms = symbols, lists = conses,
  compounds = simple-vectors, variables = a small struct), so no custom collector is needed.

Size: about 2300 lines of Lisp. Requirements: `sbcl` (tested with 2.6.x); `swipl` only for the SWI comparison.

Contents: [1. Running a program with `./qp`](#1-running-a-program-with-qp) ·
[2. Comparing with SWI-Prolog](#2-comparing-with-swi-prolog) · [3. Using the SBCL REPL](#3-using-the-sbcl-repl) ·
[4. Syntax and quirks](#4-syntax-and-quirks) · [5. Is it as efficient as SWI-Prolog?](#5-is-it-as-efficient-as-swi-prolog) ·
[6. Tests, layout, limitations](#6-tests-layout-limitations) ·
[7. System predicates: shell commands, processes, environment](#7-system-predicates-shell-commands-processes-environment)

All commands below are typed in a terminal, **inside the qprolog folder** (`cd ~/csand/qprolog`).

---

## 1. Running a program with `./qp`

A qprolog program is a text file of Lisp forms, mostly clauses `(<- head body…)`. Running it takes two steps:
*load* the clauses, then *ask a goal*. `./qp` does both.

```
./qp FILE                 # load FILE, ask the goal  top  (a program's "main"), print yes/no and the time
./qp FILE GOAL            # load FILE, ask GOAL, print the first solution
./qp FILE GOAL -a         # ... print all solutions
./qp                      # print a short usage message
```

`GOAL` is a Lisp list in single quotes, so the shell does not touch the parentheses or the `?`.
`FILE` may also be an ordinary Prolog text file (`prog.pl`): it is translated on the fly, so
`./qp prog.pl '(app (1 2) (3) ?z)'` works without a separate `./tr.x` step (the goal is still written in
qprolog's syntax).

Examples:

```
./qp bench/programs/sieve.lisp                                # runs top; prints  (TOP)  yes (0.040 s)
./qp bench/programs/tak.lisp '(tak 18 12 6 ?a)'               # prints (TAK 18 12 6 7): ?a was bound to 7
./qp bench/programs/sieve.lisp '(:and (top) (prime 9973))'    # two goals in a row; yes because 9973 is prime
./qp app.lisp '(app ?x ?y (:l a b c))' -a                     # all four ways to split the list [a,b,c]
```

What to remember:

* **The output is your goal with its variables filled in.** `(TAK 18 12 6 7)` is the goal `tak(18,12,6,A)`
  with `A = 7`. With `-a` you get one line per solution and a count.
* **`yes` / `no`** is the truth of the goal; the time is for running the goal, not for loading the file
  (clauses are compiled the first time they are called, so a first call includes some compile time).
* **No `top`, no goal?** `./qp app.lisp` looks for `top/0`, does not find it and says so. Only the benchmark
  files define `top`; for your own files, give a goal.
* **Every `./qp` call is a fresh process.** Facts asserted by one call are gone in the next. To keep state, use
  the REPL (section 3).
* **Your file may be anywhere:** `./qp ~/myprogs/app.lisp '(app (1 2) (3 4) ?z)'`. Run `./qp` from the qprolog
  folder, or by its full path (`~/csand/qprolog/qp`).
* **Errors** are printed as `error: (ERROR (EXISTENCE_ERROR PROCEDURE (/ NOSUCH 0)) …)` — here, "no predicate
  `nosuch/0`" — and the exit code is 1.
* Programs that print (`write`, `nl`, `format`) print before the `yes` line.

### Writing your own program

Put clauses in a file, one `(<- head body…)` per clause; a fact has no body. `app.lisp` (list append):

```lisp
(<- (app () ?x ?x))
(<- (app (?x . ?xs) ?y (?x . ?z))
    (app ?xs ?y ?z))
```

```
./qp app.lisp '(app (1 2) (3 4) ?z)'        # (APP (1 2) (3 4) (1 2 3 4))   yes
./qp app.lisp '(app ?x ?y (1 2 3))' -a      # 4 solutions
```

A file is really a Lisp file: `;` starts a comment, and any form that is not `(<- …)` is evaluated as Lisp
(that is how `(declare-dynamic '(/ p 1))` works). If you already have a Prolog program in ordinary syntax,
translate it with `./tr.x`:

```
./tr.x exs/p01-015.pl p01-015.lisp      # IN.pl  OUT.lisp
./tr.x exs/p01-015.pl                   # OUT defaults to the input name with .lisp:  exs/p01-015.lisp
./qp p01-015.lisp '(compress (:l a a b c c) ?r)'
```

It prints `IN -> OUT` on success; on a syntax error it says where and exits with status 1.

The translator handles operators, `is`, if-then-else, DCG rules and directives such as `:- dynamic`. It
writes `[H|T]` as `(?h . ?t)`, `[a,b]` as `(:l a b)`, and so on (section 4). `bench/programs/*.lisp` were
made this way from the classical benchmark sources.

---

## 2. Comparing with SWI-Prolog

Needs `swipl` and `sbcl` on the PATH. From the qprolog folder:

```
./bench/vs-swi.sh            # every program about 1 s in SWI; one run each; takes a few minutes
./bench/vs-swi.sh 0.2 3      # 5x fewer iterations, median of 3 runs (faster, a bit noisier)
```

It runs SWI-Prolog's own timing harness (`bench/swi/run.pl`) and qprolog on the same 15 classical benchmarks
(boyer, browse, chat_parser, crypt, derive, det, divide10, fast_mu, reducer, sendmore, serialize, sieve,
simple_analyzer, tak, zebra) and prints one table: milliseconds per call in each system and the ratio
*qprolog / SWI* (below 1 means qprolog is faster). The raw numbers land in `results/swi.N.csv` and
`results/qp.N.csv`. Both systems use the same method as SWI's `run.pl`: time N × `\+ \+ top`, then subtract the
time of N × `\+ \+ dummy`, so loop overhead cancels.

Other checks, each one command:

```
./bench/check-qprolog.sh                # are the answers identical to SWI's? (compares with bench/out/check-*.swi)
./bench/run-all.sh 1.0 > qp.csv         # time qprolog only
./bench/run-qprolog.sh tak 100          # one program, 100 iterations; prints one CSV line
```

`./bench/compare.sh 1.0 results/swi.*.csv results/qp.*.csv` re-prints the table from saved CSV files.
(`results/lispy.*.csv` are timings of the earlier Lispy engine; add them to the command to include it.)

---

## 3. Using the SBCL REPL

The REPL keeps the database between goals, which `./qp` cannot.

```
sbcl --load load.lisp                            # start SBCL and load qprolog (quiet)
* (qp::load-qp "bench/programs/sieve.lisp")      ; load a program
* (qp::solve-one '(top))                         ; first solution:   T (QPROLOG::TOP)
* (qp::solve-all '(prime ?p))                    ; all solutions:    T ((QPROLOG::PRIME 2) (QPROLOG::PRIME 3) …)
* (qp::solve-one '(prime 9973))                  ; T ((QPROLOG::PRIME 9973))   -- state kept from (top)
* (qp::add-clause '(colour red) nil)             ; add a fact:  add-clause HEAD BODY-LIST
* (qp::add-clause '(dark ?c) '((colour ?c)))     ; add a rule:  dark(C) :- colour(C)
* (qp::solve-all '(dark ?c))                     ; T ((QPROLOG::DARK QPROLOG::RED) (QPROLOG::DARK QPROLOG::BLUE))
* (sb-ext:exit)
```

The whole API:

| call | meaning |
|---|---|
| `(qp::load-qp "file.lisp")` | load a program file (evaluates each form; `(<- …)` adds a clause) |
| `(qp::solve-one GOAL)` | first solution; returns two values: `T` or `NIL`, and a list holding the goal with its variables bound |
| `(qp::solve-all GOAL)` | all solutions; returns two values: `T` or `NIL`, and the list of bound goals, one per solution |
| `(qp::add-clause HEAD BODY-LIST)` | add a clause programmatically |
| `(qp::declare-dynamic '(/ name arity))` | declare a dynamic predicate (allows assert/retract, calls fail instead of erroring when empty) |
| `(qp::reset-database)` | forget all user predicates |

Notes:

* Load `load.lisp` **once per image**. Loading it twice loads the library twice, and library predicates then give
  duplicate solutions. (`tests/basic.lisp` loads `load.lisp` itself; do not `--load` both.)
* You may type goals in any package (`CL-USER` at the prompt is fine): atoms are mapped to the `QP` symbol of
  the same name. Results print with `QPROLOG::` prefixes; type `(in-package :qp)` first to drop them.
* A Prolog error (unknown predicate, type error, an uncaught `throw`) is signalled as a Lisp error, so the SBCL
  debugger appears (unless your setup handles errors). Type `(abort)` to return to the prompt; `./qp` prints the
  error as `error: …` instead.
* There is no interactive `?-` prompt. `.pl` files can be loaded directly: `(qp::consult-pl "prog.pl")`, or
  `(qp::load-qp "prog.pl")`, or from Prolog `(consult "prog.pl")` — the text is translated on the fly (section 7).

---

## 4. Syntax and quirks

qprolog terms are Lisp data. Prolog `f(X, g(a), [1,2])` becomes `(f ?x (g a) (1 2))`. This is compact and
needs no operator parser, but a few things differ from what your fingers expect.

### The basics

| Prolog | qprolog | note |
|---|---|---|
| `foo.` | `(<- (foo))` | fact; a clause is `(<- head goal1 goal2 …)` |
| `p(X) :- q(X), r(X).` | `(<- (p ?x) (q ?x) (r ?x))` | body goals are just listed |
| `X`, `Xs`, `_` | `?x`, `?xs`, `_` | variables start with `?`; `_` is anonymous |
| `f(a, 1, 2.5)` | `(f a 1 2.5)` | compound; floats are double precision |
| `foo` (atom) | `foo` | atoms are Lisp symbols |
| `[]` | `()` or `nil` | the empty list |
| `[H\|T]` | `(?h . ?t)` | dotted pair, as in Lisp |
| `[1,2,3]` | `(1 2 3)` | list of numbers — see the `:l` rule below |
| `[a,b,c]` | `(:l a b c)` | list starting with an atom — needs the `:l` marker |
| `[a,b\|T]` | `(:l a b :tail ?t)` | list with a tail |
| `"text"` | `"text"` | string |
| `X = Y` | `(unify ?x ?y)` | **`=` is arithmetic equality, not unification** (see below) |
| `X is E` | `(is ?x (+ ?a 1))` | arithmetic in prefix form: `(+ 1 2)`, `(* 2 3)`, `(mod 7 2)`, `(// 7 2)` |
| `A =:= B`, `A =\= B` | `(= ?a ?b)`, `(/= ?a ?b)` | arithmetic comparison; also `<`, `>`, `<=` (for `=<`), `>=` |
| `A \= B` | `(\\= ?a ?b)` | note the doubled backslash |
| `A == B`, `A \== B` | `(== ?a ?b)`, `(\\== ?a ?b)` | |
| `\+ G` | `(\\+ g)` | |
| `( C -> T ; E )` | `(:or c -> t e)` | if-then-else |
| `( A ; B )` | `(:or a b)` | disjunction |
| `( A , B )` in a body | `(:and a b)` | conjunction as one goal |
| `!` | `!` | cut |
| `:- dynamic p/1.` | `(declare-dynamic '(/ p 1))` | a Lisp form in the file, outside any clause |

### The quirks

1. **Lists starting with an atom need `:l`.** In `(f a b)` the first element is the functor, so `(a b c)` is
   the compound `a(b,c)`, not the list `[a,b,c]`. Write `(:l a b c)`. Lists that start with a number, a
   variable, or a compound are unambiguous and need no marker: `(1 2 3)`, `(?x ?y)`, `((f 1) (g 2))`. If a
   list of atoms "mysteriously" fails, look here first. Example: `(app ?x ?y (a b c))` finds one solution
   (the compound splits only as `[] + itself`), `(app ?x ?y (:l a b c))` finds four.
   Results follow the same convention: a list of atoms is printed `(:L A B C)`, and a bare `(A B C)` in an
   answer is a compound.
2. **A list with a tail needs `:tail` unless the tail is a plain variable.** `(?x . ?xs)` and `(1 2 . ?t)` are
   fine (dotted). `(:l a b :tail ?t)` is the form for atoms; use it whenever the tail is a compound.
3. **Atoms are case-insensitive, and print in upper case.** The Lisp reader folds `foo`, `Foo` and `FOO` into
   one atom `FOO`. `write(hello)` prints `HELLO`; `atom_codes(hello, L)` gives the codes of `HELLO`. To keep the
   case, quote with bars: `|hello|`, `|Foo|`. Quoted Prolog atoms without capital letters are folded too, so
   `'abc'` and `abc` are the same atom.
4. **Variable names are case-insensitive too.** `?X` and `?x` are the same variable, and so are `?Xs` and
   `?XS`. (The translator renames the second one automatically: `?xs1`.)
5. **`=` is not unification.** `X = Y` is `(unify ?x ?y)`; `(= ?a ?b)` compares numbers, like Prolog's `=:=`.
   Writing `(= ?x foo)` by habit raises an error (an unbound variable is not a number) rather than binding `?x`.
6. **Backslashes are doubled** in Lisp source: `\+` is `\\+`, `\=` is `\\=`, `\==` is `\\==`. A single
   backslash disappears when the Lisp reader reads the symbol.
7. **`nil` is `[]`.** `()` and `nil` are the same object, so the atom `nil` cannot be written plainly; use
   `|nil|` (the translator does this). An empty list also prints as `NIL`. Likewise `'[]'` (the atom) and `[]`
   (the list) are the same thing, as in old Prolog systems.
8. **Atoms that start with `?` are variables**, so the atom `?` cannot be written (the translator renames it
   `$q?`).
9. **Special characters need bars:** an atom containing spaces, parentheses, `;`, `.` or `|` is written
   `|my atom|`. A lone `.` is the dotted-pair separator.
10. **Control words start with a colon:** `:or`, `:and`, `:l`, `:tail`. A term such as `(:or a b)` is control
    when it appears as a goal, but ordinary data when it appears as an argument (`(unify ?x (:or a b))` binds
    `?x` to the term).
11. **Each goal is a list, so a goal without arguments is a bare symbol or a one-element list:** `(nl)`,
    `(true)`, `!`. Both `nl` and `(nl)` work as goals.
12. **Comparison of standard order:** Var < Number < String < Atom < Compound, atoms by name ignoring case;
    variables by age. (Implementation-defined, as in ISO.)
13. **Not (yet) supported:** modules, `assoc`/`pairs`/`dicts`, tabling, string functions beyond the basics,
    `read/1`, and exceptions from inside `findall` are simple. The
    library has the classics: `append`, `member`, `reverse`, `nth0/nth1`, `last`, `sum_list`, `max_list`,
    `min_list`, `select`, `delete`, `exclude/include`, `maplist/2..4`, `foldl`, `list_to_set`, `msort/sort/keysort`,
    `findall`, `setof/bagof` (see limitations), `aggregate_all`, `forall`, `between`, `length`, `atom_*`,
    `assert*/retract*`, `catch/throw`, `format`, `write`.

---

## 5. Is it as efficient as SWI-Prolog?

**On the classical benchmarks, yes — usually faster, sometimes slower.** Same machine, same method, ms per
call, median of 3 runs (times from my Linux test sandbox; run `./bench/vs-swi.sh` to get the table on your own
machine):

| program | SWI ms/call | qprolog ms/call | qprolog / SWI | earlier Lispy engine / SWI |
|---|---:|---:|---:|---:|
| boyer | 16.57 | 22.77 | 1.4× | 16.5× |
| browse | 22.63 | 28.81 | 1.3× | 7.9× |
| chat_parser | 7.23 | 5.62 | 0.8× | 3.7× |
| crypt | 0.413 | 0.106 | 0.3× | 1.6× |
| derive | 0.0036 | 0.0030 | 0.8× | 6.9× |
| det | 7.11 | 2.09 | 0.3× | 6.5× |
| divide10 | 0.0016 | 0.0013 | 0.8× | 5.7× |
| fast_mu | 0.0569 | 0.0364 | 0.6× | 3.5× |
| reducer | 1.68 | 1.61 | 1.0× | n/a |
| sendmore | 8.18 | 1.79 | 0.2× | 1.9× |
| serialize | 0.0151 | 0.0115 | 0.8× | 4.9× |
| sieve | 19.39 | 13.07 | 0.7× | 2.0× |
| simple_analyzer | 0.875 | 0.630 | 0.7× | n/a |
| tak | 6.90 | 3.78 | 0.5× | 5.8× |
| zebra | 1.35 | 1.84 | 1.4× | 4.1× |
| **geometric mean** | | | **0.7×** | **4.5×** |

Below 1 means qprolog is faster. The geometric mean of 0.7 says qprolog needs about 70 % of SWI's time (roughly
1.4× faster), and about 6× faster than the earlier Lispy engine. It wins on 11 programs, ties on 1, and loses on
three (boyer, browse, zebra: 1.3–1.4× slower). For scale: CxProlog, measured earlier in this project, came out
at about 1.7× SWI's time.

Where the answer is *no*, or "it depends":

* **Start-up cost.** SWI starts in a few milliseconds. qprolog compiles each clause with SBCL's `compile` the
  first time it is called, which costs real time: about 0.02 s for tak, 0.4–0.6 s for boyer, reducer and
  simple_analyzer, and about 1.4 s for chat_parser (column "load+warm" in `compare.sh`). The benchmark numbers
  above exclude this warm-up. For a program that runs for a fraction of a second, SWI wins; for one that runs
  for several seconds, qprolog does.
* **Only 15 programs, one machine.** They are the classical, mostly deterministic, small-data programs.
  boyer, browse and zebra (deep term building, first-argument-only indexing) show where the engine is weakest.
  Programs dominated by assert/retract, large findall results, atom/string processing, or exceptions are
  not covered, and SWI's C library for those is very well tuned.
* **Memory.** Terms are Lisp objects under SBCL's generational GC, with the heap set to 4 GB by `./qp` and
  the bench scripts. Very deep recursion is limited by the control stack (`--control-stack-size 512MB` there);
  a plain `sbcl` REPL has a smaller default.
* **Features SWI has and qprolog lacks:** see section 4, quirk 13, and the limitations below.
* **Correctness is checked the same way:** 13 of 15 programs print identical answers to SWI's on the query
  sets in `bench/check/`; the two exceptions are explained under "Correctness".

Short version: on classic benchmark code qprolog matches or beats SWI-Prolog; it is not a replacement for it.

---

## 6. Tests, layout, limitations

```
sbcl --non-interactive --load tests/basic.lisp          # 93 unit tests; prints "93 tests, 93 passed, 0 failures"
QP_VERBOSE=1 sbcl --non-interactive --load tests/basic.lisp   # ... and one "ok" line per test
QP_DEBUG=1 sbcl --non-interactive --load tests/basic.lisp     # the same tests on the slow, fully checked build
```

| path | contents |
|---|---|
| `qp`, `qp.lisp` | the command-line runner (section 1) |
| `tr.x`, `tr.lisp` | the command-line Prolog-to-qprolog translator (section 1); it uses `bench/pl2lispy.lisp` |
| `load.lisp` | loads the system (source order: package, machine, terms, database, compiler, runtime, builtins, library) |
| `src/machine.lisp` | registers, `deref`/`bind`/trail, generic `unify`, frames, choice points, `backtrack`, trampoline `run` |
| `src/terms.lisp` | clause templates, `instantiate`, `unify-tpl`, surface-syntax conversion, `copy-term`, arithmetic, standard order |
| `src/database.lisp` | predicates, clauses, first-argument keys, dynamic database (logical update view, lazy hash index) |
| `src/compiler.lisp` | goal normalisation, control constructs (aux predicates, inline `\+` / if-then-else on tests), head/body code generation, chunking |
| `src/runtime.lisp` | dispatchers, `call/N`, nested runs (`solve-iter`/`solve-once`), catch/throw, program loading |
| `src/builtins.lisp` | Lisp-coded builtins (type tests, arithmetic, atoms/strings, assert/retract, findall, sorting, I/O …) |
| `src/system.lisp` | shell commands, external processes, environment, files (section 7) |
| `src/consult.lisp` | `consult/1`, `consult-pl`: load ordinary Prolog text via the translator |
| `lib/library.lisp` | library predicates written in Prolog (append, member, maplist, foldl, setof/bagof …) |
| `lib/pipeline.lisp` | optional library: run a numbered pipeline of external scripts (section 7) |
| `bench/` | benchmark programs (`programs/`), SWI sources and harness (`swi/`), query sets (`check/`), scripts, translator |
| `results/` | CSV timings: SWI, qprolog and the earlier Lispy engine |

How it executes: a trampoline — each compiled chunk returns the next function to run, which gives proper
last-call optimisation and no Lisp stack growth. Predicates with several clauses get a dispatcher on the first
argument; a choice point is created only if two or more clauses can match. The build is `safety 0` (fast) by
default; `QP_DEBUG=1` (or `:qp-debug` in `*features*`) selects a checked build.

### Correctness

All 15 programs run with `ok=yes`, and query outputs are identical to SWI-Prolog's for 13 of them
(`./bench/check-qprolog.sh`). The two differences are understood and are not engine bugs:

* `chat_parser`: the atom `?` is renamed by the translator (`$q?`).
* `simple_analyzer`: `atom_codes('abc', L)` gives the codes of `ABC`, because atoms are case-folded (quirk 3).

### Known limitations

* Atom and variable names are case-insensitive (quirks 3–4); `'[]'` and `[]` are the same (quirk 7).
* `setof/bagof` are built on `findall` and do not implement free-variable (`^`) grouping.
* After a nondeterministic exit from `catch/3`, the catch frame stays active for the continuation (a small
  deviation from ISO scoping of `catch`).
* Standard order is SWI-7-like (Var < Number < String < Atom < Compound), atoms compared case-insensitively;
  variable order is by creation time (implementation-defined).
* Control terms built at run time and called (`call((A,B))`) are compiled anew each time — slow in tight loops.
* No modules, no tabling, no `read/1`. `consult/1` translates Prolog text with `pl2lispy` (operators, DCGs and
  `:- dynamic` work; other directives are rejected).

---

## 7. System predicates: shell commands, processes, environment

These are what a script needs to drive other programs. Text arguments (commands, program names,
arguments, paths, variable names) may be strings, atoms or numbers. **Use strings** (`"ls -l"`): atoms are
case-folded, so `ls` would be the atom `LS`.

| predicate | meaning |
|---|---|
| `shell(Cmd)` | run `Cmd` with `/bin/sh -c`; succeeds iff the exit status is 0 |
| `shell(Cmd, Status)` | the same; `Status` is the exit status (an integer; 128+N if killed by signal N) |
| `shell_output(Cmd, Status, Output)` | the same, and `Output` is the command's standard output as a string |
| `process_run(Prog, Args, Status)` | run `Prog` (searched on `PATH`) with the list `Args`, no shell, so nothing to quote |
| `process_run(Prog, Args, Options, Status)` | with options `cwd(Dir)`, `env(["NAME=value", …])` (added to the environment), `capture(Output)` |
| `getenv(Name, Value)` | value of an environment variable, as a string; **fails** if it is not set |
| `getenv_or(Name, Default, Value)` | like `getenv`, but `Value = Default` when it is not set |
| `current_executable(Path)` | the path of the running `sbcl` |
| `exists_file(Path)`, `exists_directory(Path)` | as in SWI-Prolog |
| `working_directory(Old, New)` | unify `Old` with the current directory; if `New` is bound, change to it |
| `halt(Code)` | flush output and exit with status `Code` (`halt` alone exits with 0) |
| `consult(File)` | load a Prolog text file (`.pl`), translated on the fly |

The child's standard input, output and error are inherited, so its output appears where a shell command's
would, in order with qprolog's own output. A program that cannot be started raises
`error(system_error(run, Message), _)`.

Example, `hello.lisp`:

```lisp
(<- (go) (shell "echo hello from the shell")
         (shell_output "date +%Y" 0 ?year)
         (process_run "ls" ("-1" "src") ((capture ?files)) 0)
         (format "year ~a~nfiles: ~a" (?year ?files)))
```

```
./qp hello.lisp '(go)'
```

### A pipeline of external scripts: `lib/pipeline.lisp`

An optional library that runs numbered stages of `sbcl --script` programs, stopping at the first failure. A
script supplies `pipeline_root/1` (the directory the stages run in) and `substep/5` facts
`substep(Stage, Position, Description, Script, ArgList)`, then asks `run_pipeline`. The umap-sarcoma repository's
`sarcoma-setup.x` is a complete example. Stages run as `SBCL --script Script Args…`, where `SBCL` is the
environment variable of that name or the current `sbcl`; a stage that exits non-zero prints
`Stage D failed with exit code N.` and stops the pipeline with status 1.
