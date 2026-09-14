# claude-prolog tutorial

A practical, run-it-yourself guide to using claude-prolog from the SBCL
REPL or a script. For the *design rationale* behind any of this --
why the reader has no operator-precedence table, why `is` is safe to
write infix, exactly how the `?` read macro disambiguates itself from
pvars -- see `NOTES.md`, which is the running design log. This file is
the shorter, practical companion: how to actually load things, in what
order, and what the REPL is telling you when something goes wrong.

If you're reading this from `~/csand/umap-sarcoma/claude-prolog/`: this
directory is a **subtree copy** of the standalone `claude-prolog` repo,
synced by `git subtree pull` from time to time (see NOTES.md's
"squashed" commits). It can lag behind. Everything in this tutorial
describes the *system*, not a specific checkout -- if a file this
tutorial mentions isn't sitting next to it, it's probably present in
`~/csand/claude-prolog` and just hasn't been subtree-pulled into this
copy yet.

## 1. The two notations

claude-prolog has always had one way to write Prolog: as Lisp
S-expressions, directly.

```lisp
(<- (parent tom bob))
(<- (grandparent ?g ?c) (parent ?g ?p) (parent ?p ?c))
(?- (grandparent tom ?c))
```

`<-` asserts a fact or rule; `?-` runs a query and prints the first
answer's bindings; `?-all` backtracks through every answer. This is
still the native representation everything else compiles down to --
`ADD-CLAUSE`, `RUN-QUERY`, and the whole interpreter in
`prolog-engine.lisp` only ever see this shape.

On top of that sits **Edinburgh notation** -- ordinary textbook Prolog
syntax, read from `.pl` files or strings by `edinburgh-reader.lisp`:

```prolog
parent(tom, bob).
grandparent(G, C) :- parent(G, P), parent(P, C).
```

Both notations produce the *same* internal clause shape and share the
*same* database -- there's no "Edinburgh mode" you switch the engine
into. You can `consult` a `.pl` file and then query it with `?-`
bracket syntax, or assert a fact with `<-` and query it with Edinburgh
syntax; it's all one database underneath.

## 2. Loading the system

Order matters, because each file assumes the previous one is already
loaded.

```lisp
(load "prolog-engine.lisp")     ; the interpreter -- always needed
(load "edinburgh-reader.lisp")  ; adds CONSULT and Edinburgh parsing
(load "mode-compiler.lisp")     ; adds MODE, for deterministic predicates -- optional
```

If you want the `?-pred(...);` query syntax at the REPL (section 5),
load `edinburgh-read-macro.lisp` instead of `edinburgh-reader.lisp`
directly -- it loads both `prolog-engine.lisp` and
`edinburgh-reader.lisp` itself, so one `load` covers everything:

```lisp
(load "edinburgh-read-macro.lisp")
```

**Common mistake #1**: don't `(load "somefile.pl")`. `.pl` files are
Edinburgh Prolog source, not Lisp -- `CL:LOAD` reads them with the
*Lisp* reader, which has no idea `%` starts a comment there. You'll
see something like:

```
The variable % is unbound.
```

The fix is `consult`, not `load` -- see section 4.

**Common mistake #2**: a `.pl` file is not an executable script either
(no shebang, and it's data, not code) -- `./family.pl` from the shell
gets you `permission denied`. Only files with a `#!/usr/bin/env -S
sbcl --script` shebang (like `sarcoma-setup-edinburgh.x`) are meant to
be run directly; `.pl` files are meant to be `consult`ed from within a
running Lisp session or script.

## 3. Bracket syntax, briefly

- `(<- (head) goal1 goal2 ...)` -- a rule. `(<- (head))` alone is a fact.
- `(?- (goal))` -- run a query, print the first answer's bindings (or `no`).
- `(?-all (goal))` -- print *every* answer, backtracking through choice points.
- `!` as a goal -- cut: discards choice points created since the current clause was entered.
- `(lisp-eval ?var lisp-form)` / `(is ?var lisp-form)` -- evaluate an
  arbitrary Lisp form and unify the result with `?var`. These two are
  the same builtin under the hood; `is` is just the more Prolog-ish name.
- `=`, `/=`, `<`, `>`, `<=`, `>=` -- unification and numeric comparison,
  as ordinary 2-ary goals: `(= ?x 5)`, `(< ?n 10)`.
- `findall`, `bagof`, `setof`, `call` -- see section 7.

Named variables are Lisp symbols starting with `?` (`?x`, `?Result`);
the underscore `_` is the anonymous variable.

## 4. Edinburgh notation: writing and consulting `.pl` files

Ordinary textbook syntax: `head(Args) :- goal1, goal2, ...` for rules,
`head(Args).` for facts, `%` for a line comment, `/* ... */` for a
block comment. Variables are capitalized or `_`-led (`X`, `Stop`,
`_`); atoms are lowercase (`red`, `count_up`... though see the
hyphen note below); strings are `"double-quoted"`; lists are
`[a, b, c]` and `[Head|Tail]`.

```prolog
% family.pl
parent(tom, bob).
parent(tom, liz).
older(X, Y) :- age(X, AgeX), age(Y, AgeY), AgeX > AgeY.
```

Load the engine and the Edinburgh reader, then:

```lisp
(consult "family.pl")
```

This prints a one-line summary (`% family.pl consulted: N clauses
installed`, or a count of errors if any clause had a syntax problem --
consult keeps going and installs every *other* clause rather than
aborting on the first typo) and leaves every fact/rule sitting in the
same database `<-` uses. From here you can query it three ways:

```lisp
(?- (older bob liz))                        ; bracket syntax, unaffected
(edinburgh-query "older(bob, liz)")         ; Edinburgh syntax, as a string
?-older(bob, liz);                          ; Edinburgh syntax, bare -- needs section 5
```

**Hyphens in names**: `count-up`, `list-len`, `register-callable` --
this codebase's own naming convention -- work fine as ordinary
Edinburgh atoms (`count-up(N, Out) :- ...`). Only variable names
exclude the hyphen (`X-1` reads as the variable `X` followed by the
number `-1`, not a variable literally named `X-1`).

**Escaping to Lisp**: a `(` in term position that *isn't* tight
against an atom (i.e. there's a space, or nothing, before it) is a
literal Lisp form, read by `CL:READ` and translated back --
`is(V, (getenv-or "SAR_EPOCHS" "200"))` or the infix spelling `V is
(getenv-or "SAR_EPOCHS" "200")` both call the Lisp function
`getenv-or` directly. Only functions explicitly registered via
`(register-callable 'some-function)` can be called this way -- it's a
deliberate whitelist (`*lisp-eval-functions*` in
`prolog-engine.lisp`), so Prolog source can't grant itself arbitrary
Lisp access. `format`, for instance, isn't registered by default; if a
`.pl` file's directive uses it, register it from Lisp *before*
consulting: `(register-callable 'format)`.

## 5. Querying with `?-pred(...);` at the REPL

`edinburgh-read-macro.lisp` (loaded per section 2) adds a Lisp reader
macro so you can type a query the way you'd type it at any Prolog top
level, instead of wrapping it in a string:

```lisp
(enable-edinburgh-syntax)
?-count-up(0, 10, Out);
(disable-edinburgh-syntax)   ; whenever you want plain Lisp reading back
```

**This has to be switched on.** Typing `?-count-up(0, 10, Out);`
*before* calling `(enable-edinburgh-syntax)` reads under the plain
Lisp reader instead, where `?` means nothing special -- you'll get:

```
The variable ?-COUNT-UP is unbound.
```

(`?-count-up` reads as one ordinary symbol, stops at the `(`, and gets
evaluated as a variable reference.) Once enabled, it stays enabled --
`*readtable*` is set globally for the rest of that session -- and
ordinary Lisp code you type in the same session reads exactly as it
always did; only the specific `?-ident(` shape (no space before the
`(`) is new. `?x`-style variables, and the older `(?- (goal))`/
`(?-all (goal))` bracket-syntax macros, are completely unaffected
either way -- you never need to choose one query style over the other
for a whole session.

The query runs up to the first `;` -- so a query with more than one
goal is just comma-separated, same as any Prolog top level:

```lisp
?-p04-count([a,b,c,d], N), p01-last(X, [a,b,c,d]);
```

**Scope limitation, found while writing this tutorial**: the bare
`?-...;` syntax only recognizes a query whose *first* goal is a
compound term -- `lowercase_atom(` sitting tight against the `(`. A
query whose first goal instead starts with a bare variable or a
number -- the shape every infix expression from section 6 has, e.g.
`X is 5` or `3 < 5` -- does **not** trigger it: `?-X is 5;` reads as
the truncated symbol `?-X`, followed by ` is 5;` left dangling as
separate (broken) input, not as an embedded query at all. This wasn't
caught by `edinburgh-read-macro-tests.lisp` because that suite predates
infix syntax; every example in it happens to start with a compound
term. Until this gets a proper fix, lead with a compound-term goal
(`?-count-up(0, 10, Out);` is fine, since `count-up(...)` is a compound
term even though its *body* uses infix `is`), or use `edinburgh-query`
as a string for anything starting with a bare variable or number:

```lisp
(edinburgh-query "3 < 5, 4 < 5")   ; works regardless of what the query starts with
```

## 6. Infix operators

Every ISO-familiar operator this reader knows -- `is`, `=`, `=:=`,
`=\=`, `=<`, `<`, `>`, `>=` -- can be written either as a
compound-term/prefix call, `is(V, Expr)`, or infix, `V is Expr`. Both
spellings parse to the identical internal term, so it's purely a
style choice; every example file in this repo now uses the infix
spelling (`N >= Stop`, `Out = N`, `Next is (+ N 1)`), since it reads
closer to ordinary Prolog.

Two things infix does *not* do, on purpose, and this is worth knowing
before writing longer expressions:

- **No chaining.** `X < Y < Z` reads `X < Y` as one complete goal and
  then hits a bare `< Z` with nothing legal to connect it to -- a
  clear syntax error, not a silent misparse. (Real ISO Prolog rejects
  this too, for the same underlying reason: these operators are all
  declared non-associative.)
- **No `and`/`or` combination.** `X < 5 and Y > 3`, `X < 5 or Y > 3`,
  and `X < 5 ; Y > 3` are all syntax errors -- `and`, `or`, and `;`
  aren't operators in this grammar at all. The safe way to combine
  goals is the same as it's always been: comma-separated, as separate
  items in a clause body or query (`X < 5, Y > 3`), never nested
  inside a single term. Combining goals into a single *term* (needed,
  for instance, to give `findall` a conjunction as its Goal argument)
  is a separate, currently-unimplemented feature -- seeing it there
  would mean real operator-precedence parsing for `,`/2 and `;`/2,
  which this reader's whole design deliberately avoids needing.

## 7. `findall`, `bagof`, `setof`, `call`

```lisp
(?- (findall ?x (item ?x ?n) ?xs))    ; bracket
?-findall(X, item(X, N), Xs);          ; Edinburgh -- starts with a compound term, so the read-macro triggers fine
```

`bagof`/`setof` behave like `findall` but additionally require at
least one solution to succeed (an empty result fails rather than
binding `[]`); `setof` also sorts and deduplicates. `call(Goal,
ExtraArgs...)` appends `ExtraArgs` onto `Goal` and runs it -- the
usual higher-order plumbing.

**Current limitation**: the Goal argument must be a single goal term,
not a `(G1, G2, ...)` conjunction -- there's no `,`/2 term operator in
this engine (see section 6's last point). `findall(X, (P(X), Q(X)),
L)` isn't supported yet.

## 8. Deterministic predicates: `mode`

For a predicate you know is functional (given the inputs, at most one
output, no need for backtracking), `mode-compiler.lisp` can compile it
straight into a plain Lisp function -- much faster than going through
the general interpreter.

```lisp
(load "mode-compiler.lisp")
(consult "det-mode.pl")           ; or any (<- ...) clauses, either notation
(mode (count-up + + -))           ; + = input position, - = output position
(moded-count-up-3 0 10)           ;=> (values t 10)
```

This works identically regardless of whether the clauses came from
`consult` (Edinburgh) or `<-` (bracket) -- the compiler reads whatever
is already sitting in the database and reconstructs each argument's
shape from the plain pattern plus the mode you declared. The one thing
that's bracket-only is the *inline* `+x`/`-x` annotation on a clause
head some `.lisp` files use as a shortcut for inferring the mode
automatically -- Edinburgh notation has no surface syntax for that (a
bare `+` or `-` there is just a symbolic atom), so for
Edinburgh-sourced clauses always declare `mode` explicitly, as above.

## 9. Quick troubleshooting reference

| What you typed | What went wrong | Fix |
|---|---|---|
| `(load "file.pl")` | `.pl` is Edinburgh source, not Lisp; `%` isn't a comment to `CL:READ` | `(consult "file.pl")` |
| `./file.pl` | not executable, no shebang -- it's data | `consult` it from a session, or run the `.x` driver script that consults it |
| `?-pred(...);` | `(enable-edinburgh-syntax)` wasn't called yet, so `?` means nothing special | `(load "edinburgh-read-macro.lisp")` then `(enable-edinburgh-syntax)` first |
| `is(X,Y)` inside a `.pl` file calling an unregistered Lisp function | that function isn't on the `*lisp-eval-functions*` whitelist | `(register-callable 'the-function)` from Lisp, before consulting |
| `X < Y < Z` or `X < 5 and Y > 3` | chaining / and-or combination isn't supported, on purpose | rewrite as separate comma-separated goals |
| `?-X is 5;` or `?-3 < 5;` (read-macro) | the query's first goal starts with a bare variable/number, not a compound term -- the `?-...;` read-macro doesn't recognize that shape yet | use `(edinburgh-query "X is 5")` (a string), or lead with a compound-term goal |

## 10. File map

- `prolog-engine.lisp` -- the interpreter: unification, the general
  solver, cut, `is`/`lisp-eval`, comparisons, `findall`/`bagof`/
  `setof`/`call`, the `register-callable` whitelist.
- `edinburgh-reader.lisp` -- the Edinburgh tokenizer/parser: `consult`,
  `edinburgh-query`, `edinburgh-term`, infix operators.
- `edinburgh-read-macro.lisp` -- the `?-pred(...);` Lisp read macro
  (`enable-edinburgh-syntax` / `disable-edinburgh-syntax`).
- `mode-compiler.lisp` -- `mode`, deterministic-predicate compilation.
- `pipeline.lisp` -- reusable "run a sequence of external stages"
  library (used by `sarcoma-setup-edinburgh.x` in umap-sarcoma).
- `*.pl` -- example Edinburgh-notation programs (`family.pl`,
  `det-mode.pl`, `1prolog-test.pl`, `99-p01-p10.pl`, ...).
- `*-tests.lisp` -- the regression suites for each of the above;
  worth reading as further worked examples.
- `NOTES.md` -- the full design log: every decision above, with the
  reasoning and the concrete tests that verified it.
