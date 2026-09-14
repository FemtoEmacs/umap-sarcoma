# claude-prolog — development notes

Notes to self (Claude) for the next time this project comes up. Written
2026-09-14. Read this before touching `prolog-engine.lisp` again.

## ORIENTATION -- read this section first, every time, before anything else

If you're reading this at the start of a new session, you have zero
memory of any earlier session on this project -- every prior
conversation about `claude-prolog` is gone except what's written down
here and in the source files themselves. That's the exact failure mode
Eduardo flagged (2026-09-14): showing up with "not the slightest idea
what we were doing." This section exists to fix that in a couple of
minutes of reading, instead of requiring a full re-read of the 1400+
lines of chronological history below (which is still here, and still
worth reading when you need the *reasoning* behind a past decision --
just not before your first move).

Do this, in order, before writing or proposing any code:

1. Read only this ORIENTATION section first.
2. Get the project's ACTUAL current state from Eduardo's machine, not
   from your assumptions or from this file's claims: stage down and
   `md5sum` `prolog-engine.lisp`, `mode-compiler.lisp`, and `NOTES.md`
   itself from `~/csand/claude-prolog` on the connected device. The
   deployed files are ground truth; this file is a description of them
   that can go stale the moment a file changes without a matching
   NOTES.md update. If something's diverged, trust the files over this
   file's narrative and reconcile before proceeding.
3. Re-run the existing test suite in a Lisp-capable sandbox (device_bash
   has no `sbcl`; stage the files down and run them where `sbcl` is
   available -- see "How to sanity-check changes here in the future"
   below) BEFORE changing anything: `mode-tests.lisp`,
   `mode-multivalue-tests.lisp`, `fortran-mode-tests.lisp`, and the
   original `1prolog-test.lisp`..`5sum.lisp`/`99/` suites. Confirm the
   state this file claims actually reproduces before building on it.
4. Read "Roadmap: becoming a full-fledged Prolog" (near the end of this
   file) for what's next. Don't invent new direction from scratch --
   Eduardo has already said where this is going; work from that unless
   he's said otherwise in the current conversation.
5. Every substantive change gets three things, not just code: a new
   NOTES.md section in the style of the ones below (what changed, why,
   how it was tested, what its limits are), deployment to the device
   with an md5sum check against the actual staged copy (never just
   "looks right locally"), and -- if the change is significant enough
   that Eduardo would want it remembered even outside this codebase --
   an update to his `/areas/claude-prolog.md` persistent-memory file
   (see the note at the very end of this file on why that file exists
   and what it's for).

### Current status (last updated 2026-09-14)

- `prolog-engine.lisp` on the device is v6: trail-based destructive
  binding, first-argument clause indexing, the standard `_` anonymous
  variable, the v5 cut-correctness fix, and a lazy per-clause compiler
  (each clause compiles to a native Lisp closure on first actual use).
  This is the general engine: real unification, resolution, choice
  points, backtracking, cut, nondeterminism.
- `mode-compiler.lisp` is a separate, purely additive file (loaded
  *after* `prolog-engine.lisp`, never modifies it) prototyping a much
  more aggressive optimization for DETERMINISTIC predicates: given a
  declared mode (which argument positions are inputs vs outputs), a
  predicate compiles to a genuine native Lisp function returning
  `(values ...)`, bypassing unification/choice-points/trail entirely --
  40-70x faster than v6's general engine on the benchmarks tried so far.
  Two front-end syntaxes exist, both feeding the same underlying
  compiler, both using ONE polarity (`+` = input, `-` = output -- there
  was briefly a second, opposite polarity for the syntax below; that was
  a mistake, caught and fixed the same day):
  - the explicit `(mode (pred + - ...))` macro, declared after a
    predicate's clauses are asserted via ordinary `<-`;
  - Fortran-style inline annotation directly in a clause head's variable
    names (`(<- (pred +in -out) ...)`), which auto-triggers compilation
    once every argument position's direction is resolved -- no explicit
    `mode` call needed.
  A moded clause's head positions can now also be COMPOUND (cons)
  patterns, e.g. `append`'s `(+x . +xs)`/`(-x . -z)` -- destructured via
  `CAR`/`CDR` on the input side, constructed via `CONS` on the output
  side (`6sum.lisp`). This costs the literal-tail-call TCO guarantee for
  predicates that specifically need it (consing onto a recursive call's
  own result, like `append` does) -- see "Compound (list) patterns"
  below for exactly why, and for the honest stack-depth numbers.
- Both of the above are still exactly what they were built to answer
  (does per-clause compilation help; does mode-declared direct
  compilation help; what should declaring a mode look like) -- NEITHER
  is merged into `prolog-engine.lisp` or its ordinary compiler, and the
  language is still missing essentially all of Prolog's standard
  built-ins. See the Roadmap section: that's explicitly the next phase,
  not a someday-maybe.

## What this project is

A small Prolog interpreter implemented in Common Lisp. Not a parser for
Prolog *syntax* — clauses are authored directly as quoted Lisp
s-expressions via the `<-` macro, so the "front end" is just Lisp reader
syntax standing in for Prolog terms. Everything else — unification,
resolution, backtracking via choice points, cut, a small set of
built-ins, and an escape hatch into real Lisp arithmetic — is
implemented from scratch in `prolog-engine.lisp`.

Files:

- `prolog-engine.lisp` — the engine itself. Load this first.
- `1prolog-test.lisp` — `count-up`: counts from 0 upward by 0.01 until
  `?n >= 10`, cuts, and unifies the result. Two-clause guarded recursion,
  the simplest example of the cut idiom used everywhere else here.
- `2prolog-test.lisp` — `count-up3`: same idiom but with an explicit
  stop argument, `(count-up3 ?n ?stop ?out)`. This is the predicate that
  triggered the heap-exhaustion bug (see below) when run as
  `(?- (count-up3 0 10000 ?result))` — a million resolution steps.
- `3app-test.lisp` — `app`: classic non-deterministic Prolog `append/3`.
  Demonstrates real backtracking: `(?-all (app ?left ?right (1 2 3)))`
  enumerates all four ways to split the list, via `choice` points rather
  than cut.
- `4length-test.lisp` — `list-len`: structural recursion computing list
  length. Not tail-recursive at the Prolog level (the `lisp-eval` that
  computes `?n` runs *after* the recursive call returns), included as a
  contrast case to the tail-recursive `count-up`/`count-up3`.

Load order is always `prolog-engine.lisp` then whichever test file, e.g.
in a fresh Lisp: `(load "prolog-engine.lisp") (load "2prolog-test.lisp")`
then `(?- (count-up3 0 10000 ?result))`.

## How the engine works

- **Terms** are plain Lisp data: conses, atoms, numbers. **Variables**
  are symbols whose name starts with `?` (`variable-p`). No general
  parser — you write terms as quoted Lisp forms.
- **Clauses** (`defstruct clause head body`) are stored in `*database*`,
  a hash table keyed by `(predicate-name . arity)` (`predicate-key`), so
  `count-up3` with 3 args and a hypothetical `count-up3` with 2 args
  would be different entries. `<-` is the macro that adds a clause.
- **Unification** is `unify*`, classic structural unification over an
  **alist of bindings** (var . value), extended via `acons`
  (`bind-var`). `prolog-deref` walks the alist to resolve a variable to
  its current value (`assoc ... :test #'eq`, so binding lookups depend
  on Lisp symbol identity, not name). `*occurs-check*` is off by default
  (`bind-var` only checks it when the special var is true).
- **Fresh variables per clause use**: every time a clause is tried
  (`fresh-clause` → `copy-and-rename`), its variables get renamed to
  brand-new symbols so different activations of the same clause don't
  collide. This is where the bug was — see below.
- **Resolution loop**: `solve-from` is a single `LOOP ... DO (SETF ...)`
  over three mutable locals — `goals` (the pending conjunction), 
  `bindings`, and `choices` (a stack of `choice` structs, each a
  snapshot of `goals`/`bindings`/`choices` to resume on backtracking).
  This is already an explicit iterative state machine, *not* Lisp-level
  recursion — `solve-from` never calls itself, so arbitrarily long
  Prolog-level recursion (like a million `count-up3` steps) never grows
  the Lisp control stack. Worth remembering: **the interpreter loop
  itself already has the iterative-trampoline property people usually
  mean by "tail call optimization"; that was never the bug.**
- **Cut** (`!`) is rewritten at clause-selection time
  (`rewrite-cuts`) into `(:cut <cut-depth>)`, where `cut-depth` is
  `(length choices)` *at the moment this clause was chosen*. Executing
  the cut goal truncates `choices` back down to that depth
  (`subseq choices 0 depth`), discarding any choice points created
  since — the standard "cut commits to clauses tried since entering
  this call" semantics.
- **Built-ins** (`builtin-p` / `builtin-step`): `:cut`, `unify`,
  `lisp-eval`, `is` (alias of `lisp-eval`), and the comparison
  operators `= /= < > <= >=`. `lisp-eval`/`is` go through
  `eval-prolog-form`, which only permits calling functions listed in
  `*lisp-eval-functions*` (extend via `(callable name)` /
  `register-callable`) — this is a deliberate whitelist, not an
  oversight; don't casually widen it without thinking about what it
  means to let arbitrary Lisp run from inside a Prolog term.
- **Query entry points**: `?-` (`run-query`/`solve-one`) returns the
  first solution only. `?-all` (`run-all-query`) walks every remaining
  choice point via `solve-next`, printing each answer — this is how
  `3app-test.lisp`'s non-deterministic split is demonstrated.
- **The `preserve-query-bindings` trick** (subtle, easy to forget): in
  `solve-from`, right before selecting clauses for a goal, if
  `rest` (remaining goals) and `choices` are both empty, the engine
  discards every binding except those needed to ground the *original
  query's* variables (`protected-vars`, computed once via `query-vars`
  and threaded through). This is what keeps the bindings alist from
  growing without bound across a long tail-recursive query: each
  recursive `count-up3` call happens to hit exactly this
  rest-empty/choices-empty condition, so bindings get trimmed back to
  ~1 entry every iteration instead of accumulating a million entries.
  It's a good design, but it is easy to break — if you ever change the
  clause bodies so the recursive call is *not* the last goal, or so a
  choice point survives across iterations, this safety net stops firing
  and bindings will grow unboundedly again.

## The bug (found and fixed 2026-09-14)

**Symptom**: Eduardo reported `(?- (count-up3 0 10000 ?result))` — a
million resolution steps, incrementing by 0.01 — died with "heap
exhausted", and asked for tail-call optimization.

**What I checked first and ruled out**: Lisp-level stack growth. As
noted above, `solve-from` is already iterative; there was nothing to
"optimize for tail calls" at that level. Confirmed empirically: after
the real fix, a million-iteration run completes fine with a completely
ordinary default heap.

**Actual root cause**: `copy-and-rename` (used by `fresh-clause` every
time any clause is tried against a goal) minted each fresh variable
name with

    (intern (format nil "?~A-~D" ...) (symbol-package term))

`intern` permanently registers the new symbol in the package's symbol
table. Interned symbols are **never garbage collected** — the package
holds a reference forever. Since every one of the million resolution
steps tries both `count-up3` clauses and each clause has 3 variables,
this leaked on the order of several million permanently-retained
symbols over the course of one query, plus the memory of the growing
package symbol hash table itself.

Reproduced directly in SBCL: running `(count-up3 0 100 ...)` (10,000
steps) grew the live symbol count in the package from 1,466 to 71,474.
Running the full query with a constrained heap (`--dynamic-space-size
128`) crashed with exactly this backtrace:

    COPY-AND-RENAME -> PUTHASH/EQ -> INSERT-AT -> GROW-HASH-TABLE
    -> "Heap exhausted, game over."

**Fix**: in `copy-and-rename`, replace `intern` with `make-symbol`.
`make-symbol` creates an *uninterned* symbol — same `symbol-name`,
same behavior under `eq`-based comparisons (which is all this engine
ever does with variable symbols) — but it is ordinary heap garbage as
soon as nothing references it anymore, so the GC reclaims old
iterations' renamed variables instead of the package hoarding them
forever. Two-line change, comment left in place explaining why.

**Verified** (in a sandboxed SBCL copy of the code — I don't have a
Lisp available in the shell I use to edit files on Eduardo's machine,
so I couldn't execute the fixed file in place, only edit it there and
verify the diff landed correctly):

- Symbol count over 10,000 iterations: flat (1,466 → 1,467) instead of
  ballooning to 71,474.
- `(?- (count-up3 0 10000 ?result))`: completes in ~4.6s, ~0.03s of
  which is GC, giving `?RESULT = 10000.009`. No heap exhaustion.
- Regression-checked all four test files against the expected output
  documented in their own comments (`count-up`, `count-up3`, `app`
  forward + all-splits, `list-len` on `nil` and a 4-element list) —
  all still correct after the change.

If Eduardo reports it still crashes on his actual machine, the first
thing to check is whether his Lisp implementation is somehow
interning inside `make-symbol` too (it shouldn't be — this is standard
CL semantics) or whether the crash is now happening somewhere else
entirely (get a fresh backtrace, don't assume it's the same bug).

## Known rough edges / things to reconsider if this comes up again

- ~~`clause-candidates` does `(reverse (copy-list (gethash ...)))` on
  every call~~ — **fixed 2026-09-14.** `add-clause` now `append`s the
  new clause onto the stored list instead of `push`ing it, so clauses
  sit in declaration order already; the lookup in `solve-from` just
  reads `(gethash (predicate-key goal) *database*)` directly, no
  `reverse`/`copy-list` needed. Clause insertion is now O(n) in the
  number of existing clauses for that predicate, but that only happens
  at load time (rarely, with few clauses), so it's a good trade for
  removing a per-resolution-step cost. Measured effect on the
  million-step `count-up3` benchmark: ~2,983,300,000 bytes consed
  before -> ~2,918,985,000 bytes after (~2.2% less garbage), wall time
  roughly 4-5% faster (both noisy, small effect either way). Confirmed
  correct: all four original test files plus `3sum.lisp`/`5sum.lisp`
  give byte-identical output to before the change, including
  `3app-test.lisp`'s non-deterministic split order (which depends on
  clause declaration order being right) and the million-step
  `count-up3` result (`10000.009`).
  **Where the real cost is instead**, if this needs to be faster: the
  bulk of the ~2.9GB consed on that benchmark is `fresh-clause`/
  `copy-and-rename` rebuilding a full fresh copy of every clause's head
  and body (with new uninterned variables) for every candidate clause,
  every single resolution step. That's the next thing to look at for
  a real speedup, not this lookup.
- No general parser for Prolog surface syntax — everything is Lisp
  s-expressions through `<-`, `?-`, `?-all`. If Eduardo ever wants to
  feed it real `.pl`-style text, that's a separate, larger project
  (tokenizer + parser layer on top of this).
- `*occurs-check*` is off by default — unification will happily build
  cyclic terms if asked to (e.g. `?x = f(?x)`), which will diverge if
  you ever try to `ground` or print such a term. Not a problem in
  practice unless a future predicate does something that can construct
  such a binding.
- `eval-prolog-form`'s whitelist (`*lisp-eval-functions*`) is a
  deliberate security/sanity boundary. `register-callable`/`callable`
  exist to extend it explicitly; don't route around the whitelist.
- The engine has no error recovery for malformed queries beyond
  whatever raw Lisp errors happen to surface (e.g. `error` calls in
  `eval-prolog-form`, `register-callable`). Fine for a personal
  sandbox project, would need hardening for anything more serious.
- **`eval-prolog-form` mishandles a variable that derefs to a LIST**
  (found 2026-09-14, while testing `mode-compiler.lisp` with lists --
  see "list processing" below; not touched, not fixed, just discovered
  and documented here). `eval-prolog-form` derefs its argument and, if
  the result is a cons, always tries to reinterpret it as a further
  nested expression (checking whether ITS car is a registered
  function) rather than ever treating a dereferenced value as a
  terminal piece of data. So `(lisp-eval ?h (car ?lst))` works fine
  when `?lst`'s current value is an atom, but the moment `?lst` derefs
  to an actual LIST -- exactly what `car`/`cdr` are for -- it breaks:
  `(car ?lst)` evaluates fine as a call (CAR is registered, `?lst`
  evaluates to e.g. `(1 2 3 4 5)`), but then that VALUE `(1 2 3 4 5)`
  gets treated as EXPR again, and `1` (its own car) isn't a registered
  function, so it errors "Function not allowed in lisp-eval: 1" instead
  of just returning `(1 2 3 4 5)`. The one existing escape hatch is
  `(quote ...)` (line `((eq (car form) 'quote) (second form))`), which
  doesn't help here since the list isn't literally quoted in the
  source, it's the RUNTIME VALUE of a variable. Worth fixing if list-
  valued `lisp-eval` arguments become common -- the fix is probably
  distinguishing "evaluate this source expression" from "this dereffed
  value is already data, stop" at the one call site in `eval-prolog-
  form` that recurses into an already-dereferenced value, rather than
  reusing the same function for both jobs. Not attempted here -- out of
  scope for a mode-compiler test file, and this rough edge only affects
  the GENERAL interpreted engine's own `lisp-eval`; the mode compiler's
  own `translate-det-expr` does not have this problem (it never re-
  dereferences an already-resolved Lisp expression), so `6sum.lisp`'s
  moded predicates using `car`/`cdr` on lists work fine -- only the
  cross-checks against the interpreted engine had to route around it.
  **Update (2026-09-14, later the same day):** since this idiom is a
  real footgun (compiles and runs fine directly, silently breaks via
  `?-`/`?-all`) and, since the compound head-pattern extension below
  landed, is essentially never necessary for list destructuring
  specifically -- `COMPILE-DET-CLAUSE` now WARNS (via `WARN`, not
  `ERROR` -- the clause is still valid and still compiles) whenever a
  clause body's `LISP-EVAL`/`IS` applies a list accessor (`car`, `cdr`,
  and the rest of `*DET-LIST-ACCESSOR-WATCHLIST*`) directly to a bare
  Prolog variable. See `SCAN-FOR-RISKY-LIST-ACCESS` in
  `mode-compiler.lisp`, called from the body-goal loop right where each
  `LISP-EVAL`/`IS` expression is extracted. It's a heuristic (walks the
  raw, pre-translation expression tree looking for `(accessor ?var)`),
  not a proof, but it's exactly what would have caught `listsum`/
  `doubled` in `6sum.lisp` before they were ever queried via `?-`. It
  does NOT fire for `LISTSUM2`/`DOUBLED2`-style clauses that destructure
  via a `(?h . ?t)` head pattern instead (see "Compound (list) patterns"
  below) -- confirmed by direct test, and by a full rerun of every
  existing test file (`mode-tests.lisp`, `mode-multivalue-tests.lisp`,
  `fortran-mode-tests.lisp`, `bench-mode.lisp`, `cross-check-multi.lisp`,
  `6sum.lisp`), all still exit 0 with no new failures -- `6sum.lisp`
  now just prints four extra `WARNING:` blocks (two for `listsum`, two
  for `doubled`) on top of its previous output.

## How to sanity-check changes here in the future

There's no Lisp installed in the sandboxed shell this session used to
edit files on Eduardo's machine directly, so verification of any future
change here should either happen in whatever Lisp Eduardo runs locally,
or by round-tripping a copy of the files into a cloud sandbox that has
SBCL (`apt-get install sbcl`) and running the four test files plus
whatever new case is in question — same approach used to diagnose and
verify the heap-exhaustion fix above.

## Files that appeared after the fix (Eduardo's own experiments)

While I was writing this documentation, three more files showed up in
the folder that weren't there when I first looked at the repo:

- `3sum.lisp` and `5sum.lisp` — both define a 4-argument `count-up`:
  `(count-up ?n ?stop ?s ?out)`, an accumulator-style extension of the
  `count-up`/`count-up3` idiom above. `?s` is threaded through as a
  running total, stepped by 0.02 each recursive call (twice the 0.01
  step on `?n`), and handed to `?out` once `?n` reaches `?stop`.
  Eduardo confirmed the purpose: `5sum.lisp` is deliberately testing
  whether a clause can end with a bare cut and no explicit `unify`
  goal, by relying on **head unification** to do the work instead.
  Its base clause's head is `(count-up ?n ?stop ?s ?s)` — the same
  variable `?s` written in both the 3rd and 4th argument positions —
  so calling it with any `?out` in the 4th position unifies `?out`
  with whatever `?s` (the accumulator) currently is, *before* the body
  even runs; the body then only needs the guard and `!`, no
  `(unify ?out ?s)` required. `3sum.lisp` is the same predicate written
  the other, more explicit way (`?s` and `?out` as distinct head vars,
  with an explicit `(unify ?s ?out)` body goal), presumably an earlier
  draft kept for comparison. I ran both patterns against the fixed
  engine: `(?- (count-up 0 100 0 ?result))` gives `?RESULT = 200.0059`,
  and the full million-step case, `(count-up 0 10000 0 ?result)`,
  gives `?RESULT = 20000.018` (`?s` steps by 0.02 while `?n` steps by
  0.01, so it should be exactly double `?n`'s range — checks out) with
  zero leftover choice points, confirming the cut discards the
  alternative clause correctly either way. So: yes, ending a clause
  with a bare cut and letting head unification alone produce the
  output works fine in this engine — nothing about `!` or the
  resolution loop depends on a `unify`/`is` goal following it in the
  body.
- `4sum.lisp~` — a `~`-suffixed file (the usual Emacs backup-file
  convention), byte-for-byte identical to `3sum.lisp`, with no
  corresponding `4sum.lisp` present. Almost certainly a stray editor
  backup from renaming/iterating through `3sum.lisp` → `4sum.lisp` →
  `5sum.lisp`, not a deliberate fourth variant. Worth mentioning to
  Eduardo next time rather than silently treating it as intentional —
  it's safe to delete but I haven't touched it.

## The `99/` folder

Working through the classic P-99 ("Ninety-Nine Prolog Problems") set,
https://www.ic.unicamp.br/~meidanis/courses/mc336/2009s2/prolog/problemas/,
as a way to find out what this engine is still missing to be a
"full-fledged" Prolog. `99/p01-p10.lisp` has problems 1-10 (list basics:
last element, last-but-one, Kth element, count, reverse, palindrome,
flatten, compress, pack, run-length encode), all solved using nothing
but what the engine already provides -- unification, cut, and
lisp-eval for arithmetic. No engine changes needed for any of them.

Two things worth remembering about *how* they're solved, since they're
not the first idiom you'd reach for from standard textbook Prolog:

- Several textbook solutions (compress/P08, pack/P09) guard their
  "different from the previous element" clause with an explicit
  `X \== Y`. This engine has no general term-inequality builtin, so
  instead these use the same-variable-twice-in-the-head trick (a
  clause head like `(?x ?x . ?xs)` forces the first two list elements
  to unify with each other) *for the "same" case*, put that clause
  first, and cut inside it -- which discards the "different" clause's
  otherwise-spurious alternative whenever the elements really are
  equal. Verified this doesn't leak extra answers under `?-all`
  (checked compress and pack on inputs with adjacent-equal elements --
  exactly one answer each, not two).
- P06 (palindrome) uses the classic `palindrome(L) :- reverse(L,L).`
  idiom -- same variable in both argument positions of a call forces
  the output to unify with the (already-ground) input.

See the running answer to "what's missing for a full-fledged Prolog"
in conversation from 2026-09-14 for the fuller gap analysis (meta-call
/ findall, term (in)equality as a first-class builtin, atom/string
ops, randomness, I/O-as-a-goal) -- worth turning into its own doc if
this project keeps going.

## Performance vs SWI-Prolog (2026-09-14)

Eduardo asked how efficient this engine is compared to SWI-Prolog.
Rather than guess, I installed SWI-Prolog 9.0.4 and ran three matched
benchmarks -- same algorithm, same clause structure as much as the two
languages allow, hand-rolled helper predicates on both sides (no SWI
builtins like `permutation/2`, `append/3`, `findall` used, so the
comparison is apples-to-apples on the resolution engine itself, not
library quality). Scripts are in `bench/` (`bench_claude_prolog.lisp`,
`bench_swi.pl`).

**Benchmark 1 -- tail-recursive arithmetic loop** (`count_up3`, the
predicate this whole project started from): 1,000,000 resolution steps.
claude-prolog: 3.7s. SWI: 0.22s wall (3,000,003 inferences, 16.5M
LIPS). **~17x slower.**

**Benchmark 3 -- 8-queens via generate-permutation-then-test-safety**,
counting all 92 solutions (real backtracking, not just tail recursion):
claude-prolog: 3.3s. SWI: 0.070s (1,098,554 inferences). **~47x
slower.**

**Benchmark 2 -- naive reverse (nrev), the classic non-tail-recursive
Prolog benchmark**: this is the one that matters most, because the
result isn't "a bigger constant factor" -- it's a different complexity
class. Scaling just the list length L (one `nrev(L)` call, not
repeated):

| L   | claude-prolog | SWI      |
|-----|---------------|----------|
| 40  | 0.020s        | ~0.0001s |
| 80  | 0.308s (15x)  | ~0.0001s |
| 160 | 18.78s (61x)  | 0.0004s (~4x, clean quadratic) |

SWI stays textbook O(L^2) the whole way (doubling L roughly
quadruples the time, exactly as nrev's complexity predicts). claude-
prolog's time roughly *15x's* going 40->80 and *61x's* going 80->160 --
nowhere near O(L^2), more like O(L^4) or worse, compounding with GC
pressure as the run gets bigger. The 200-reps-of-nrev(100) form of this
benchmark (the "natural" benchmark size) does not finish in over 2
minutes on claude-prolog; SWI does it in 0.03s.

**Why the gap is a constant factor in benchmarks 1 and 3 but blows up
in benchmark 2**: `count-up3` and (mostly) the queens search stay in
exactly the shape where `solve-from`'s `preserve-query-bindings`
trimming trick (documented above, under "How the engine works") fires
every iteration -- the goal is in tail position with an empty choice
stack, so bindings get discarded back down to ~O(1) size constantly.
`nrev`'s recursive call to itself is *not* the last goal in its clause
body (`myapp` runs after it), so that trimming condition never fires
during the recursive descent -- bindings for the whole call accumulate
in one global alist for the entire O(L) depth, and since every
`prolog-deref`/`unify*` does a linear scan of that alist, the real
per-step cost grows with how deep into the call you already are. This
is *not* a niche case -- most natural Prolog code (anything that does
something with a recursive call's result, rather than making the
recursive call the very last thing in the clause) has this shape.

**Root causes, for real, if this ever needs to get faster** (roughly
in order of expected impact):

1. **Bindings representation.** The alist + `preserve-query-bindings`
   trimming is a clever patch for the one shape where it works, but a
   real fix is structural: give each logic variable its own mutable
   binding cell (bind destructively, record the variable on an
   undo/"trail" list, unbind on backtrack) instead of consing an
   ever-growing association list. This is exactly what WAM-based
   engines (SWI included) do, and it turns dereference from O(current
   bindings size) into O(1). This single change would very likely
   close most of benchmark 2's gap and make the `preserve-query-
   bindings` hack unnecessary.
2. **Full clause copying on every candidate try.** `fresh-clause`/
   `copy-and-rename` rebuilds an entire fresh copy of a clause's head
   and body -- new cons cells, new uninterned symbols via
   `make-symbol` -- for *every* clause of a predicate, on *every* call,
   before even checking whether it unifies. SWI compiles clauses once
   and reuses a shared representation with a small per-call
   environment/binding frame. This is already flagged as the "known
   rough edge" above (`fresh-clause`/`copy-and-rename` being the bulk
   of consing on benchmark 1) -- it's a bigger deal than it looked
   before this benchmark, since it's paid on every clause of every
   predicate, every call, everywhere, including all the useless
   attempts against clauses that don't end up matching.
3. **No clause indexing.** Related to (2): SWI uses first-argument (and
   deeper) indexing to skip clauses that can't possibly match without
   even trying to unify against them. This engine always tries every
   clause of a predicate, in order, every time. Doesn't matter much
   for 2-4-clause predicates (everything written here so far), would
   matter a lot for predicates with many clauses (e.g. a large fact
   database).

**Bottom line**: for code written in the careful tail-recursive-with-
cut idiom this project has used throughout (which most of it has, by
necessity, to avoid the original heap-exhaustion bug), claude-prolog
is "only" 15-50x slower than a production Prolog with three decades of
WAM engineering behind it -- a genuinely reasonable number for an
interpreter like this. But that ratio should NOT be assumed to hold
for arbitrary Prolog code, including some of the P-99 problems
themselves if written in the more natural (non-tail-recursive) style --
nrev is proof that the gap can become a different complexity class,
not just a bigger constant, the moment a predicate's recursive call
isn't the last goal in its clause. Worth checking any P-99 solution
that builds up a result "on the way back up" the recursion (rather
than threading an accumulator) at realistic input sizes before trusting
it'll finish in reasonable time.

## The v2 rewrite (2026-09-14): closing the gap with SWI-Prolog

Eduardo's instruction for this round: "preserve this version... practically
Patrice Boizumault's *The Implementation of Prolog*... I made a copy of it
called patrice-prolog. Now, try to close the gap as you suggested. If you
run in serious error, it is possible to backtrack to patrice-prolog."

**`~/csand/patrice-prolog` is a full snapshot of the pre-rewrite engine**
(the alist-bindings, full-clause-copying design analyzed in the section
above). It has NOT been touched by this rewrite and remains the rollback
target if v2 turns out to have a serious problem. `prolog-engine.lisp` in
*this* directory (`claude-prolog`) is now v2.

### What changed, and why

The previous section's root-cause list named three things. This rewrite
addresses the first two:

1. **Bindings representation (root cause #1, addressed).** Instead of an
   immutable alist threaded through every call, each logic variable is now
   a mutable cell (a `pvar` struct: `value`/`name`/`id`). Binding a variable
   is a destructive `setf` on that cell, recorded on a global adjustable
   vector called the *trail*. Backtracking undoes bindings by walking the
   trail back to a saved mark and resetting each cell to `+unbound+`, newest
   first. Dereference (`pderef`, renamed from `deref` because `deref` is a
   locked symbol in `SB-ALIEN` and SBCL refused to let a plain `CL-USER`
   function shadow it) is now `O(1)` instead of a linear alist scan -- this
   is what a WAM-style engine does, and it's the change that fixes nrev's
   complexity-class problem (see numbers below).

   There's one soundness assumption worth remembering if this code ever
   grows nested/interleaved queries: `maybe-clear-trail` clears the whole
   trail whenever the choice-point stack is empty, as a cheap stand-in for
   real WAM-style *conditional trailing* (which only trails a binding if
   the variable predates the current choice point). This is safe for every
   usage pattern in this codebase today (one query resolves to completion,
   or is driven by `solve-one`/`solve-next`, before the next one starts),
   because the trail and choice-point stack are both global and a query
   never runs concurrently with another one's undo. It would NOT be safe if
   something started keeping multiple independent queries' choice points
   alive at once and interleaving backtracking between them arbitrarily --
   that would need real per-choice-point trail marks (already half-present
   via `trail-mark`/`undo-to`, just not used for anything finer-grained than
   whole-query clearing yet).

2. **Full clause copying on every candidate try (root cause #2, addressed).**
   v1's `clause-candidates` renamed (fresh-copied) both the head *and* body
   of every clause of a predicate before checking whether any of them
   unify. v2's `try-clauses` is lazy and sequential: for each clause in
   turn, it copies (`instantiate`) and unifies *only the head* first; only
   if that succeeds does it instantiate the body and proceed; if a clause
   fails, everything the head-unify did gets undone via the trail
   (`undo-to`) before the next clause is even instantiated. This also fixed
   a correctness hazard that doesn't exist with the old immutable-alist
   design: with destructive binding, you *cannot* safely try unifying
   multiple clause heads against the same call and collect all the
   successes up front the way v1 conceptually did, because a successful
   head-unify mutates the call's own shared variables -- if you don't undo
   before trying the next clause, that clause is unifying against an
   already-partially-bound call, not the original one. Sequential
   try-then-undo-if-fail avoids this by construction.

3. **Clause indexing (root cause #3, NOT addressed).** Still tries every
   clause of a predicate in declaration order, every call, with no
   first-argument indexing to skip obviously-non-matching clauses. Not a
   problem for anything in this codebase so far (predicates have at most a
   handful of clauses), but would matter for a large fact database. Left
   for a future round if it's ever needed.

Everything else -- the `<-`/`?-`/`?-all` macro surface, cut-via-rewriting-
to-`(:cut depth)`, the `lisp-eval`/`is` arithmetic escape hatch, the
choice-point-stack-based iterative `solve-from` (still not Lisp-recursive,
so still safe against Prolog-level recursion depth) -- is unchanged in
behavior; v2 is a drop-in replacement.

### Verification

Full regression run against the actual deployed file (not just the sandbox
copy): all of `1prolog-test.lisp`, `2prolog-test.lisp`, `3app-test.lisp`,
`4length-test.lisp`, `5sum.lisp`, and all ten `99/p01-p10.lisp` problems,
plus backtracking-count sanity checks on `p08`/`p09`, produced output
identical to v1. Also cross-checked an occurs-check/cyclic-term edge case,
`callable`/`random`, `trace-prolog`, and cut-under-`?-all` against v1's
behavior -- no regressions found.

### Performance: v1 vs v2 vs SWI-Prolog (re-measured against the deployed file)

| Benchmark | v1 | v2 | SWI-Prolog | v2 speedup over v1 |
|---|---|---|---|---|
| count-up3, 1,000,000 tail-recursive steps | 3.7s | 1.79s | 0.22s | ~2.1x |
| 8-queens, count all 92 solutions | 3.3s | 0.84s | 0.070s | ~3.9x |
| nrev on a 160-element list (single call) | 18.8s | 0.020s | 0.0004s | ~940x |
| 200 reps of nrev on a 100-element list | did not finish in 2 min | 0.93s | 0.03s | (v1 never finished) |

(Table syntax for reference only -- this file has no Markdown renderer in
play, just read it as plain text.)

The nrev scaling curve is the most important result. v1 was *superlinear
in the wrong way* -- doubling the list length from 80 to 160 made it 61x
slower, meaning the per-call cost was growing with total bindings
accumulated, not just list length. v2's scaling, remeasured end-to-end:

  L=10:    0.0000s
  L=20:    0.0000s
  L=40:    0.0000s
  L=80:    0.0040s
  L=160:   0.0200s
  L=320:   0.0600s
  L=640:   0.2520s
  L=1280:  1.0880s

Doubling L from 640 to 1280 is now ~4.3x slower, close to the ~4x a
properly O(L^2) naive-reverse should show (nrev is inherently quadratic --
that's the algorithm, not the engine -- so ~4x per doubling is the correct,
expected shape, not itself a further optimization target).

**Bottom line**: v2 closes the "different complexity class" gap entirely --
nrev now scales the way naive reverse is supposed to scale in any
correctly-implemented Prolog -- and cuts the constant-factor gap on the
other two benchmarks roughly in half to a third. The remaining ~2-4x
constant-factor gap against SWI-Prolog on count-up3/queens is what's left
of root cause #2 (still copying whole clause bodies, just lazily now
instead of eagerly) plus SWI's three decades of WAM compilation -- closing
that further would mean actually compiling clauses instead of
tree-walking a copied S-expression every call, a much bigger undertaking
than this rewrite. Root cause #3 (indexing) is untouched and would only
start to matter with much larger clause databases than anything written
here so far.

### If this needs to be revisited

- Rollback: `~/csand/patrice-prolog` has the complete pre-v2 snapshot
  (engine + all test files + `99/` + `bench/` + this NOTES.md as it stood
  before this section was added). Copy `prolog-engine.lisp` back from
  there (and anything else that changed) to undo the rewrite entirely.
- `bench/bench_claude_prolog.lisp` and `bench/bench_swi.pl` still load
  correctly against v2 unchanged (they only use the public `<-`/`?-`/
  `solve-one`/`solve-next` surface) and are the scripts to rerun for a
  fresh before/after comparison if the engine changes again.
- The `maybe-clear-trail` assumption above (single-query-at-a-time) is the
  one thing about v2's soundness that's worth re-checking first if a
  future change starts running multiple queries with overlapping
  lifetimes.

## v3: first-argument clause indexing (2026-09-14)

Eduardo's instruction: "I think you can use Clause indexing too, since we
intend to scale the codebase." This addresses root cause #3, the one item
the v2 rewrite (previous section) deliberately left alone.

### What changed

v2 always tried every clause of a predicate, in declaration order, on
every call -- even clauses whose first argument obviously couldn't unify
(e.g. trying `mklist(0, nil)` against a call `mklist(5, T)` was always
going to fail, but v2 paid for a full instantiate+unify* attempt anyway).

v3 adds first-argument indexing. Each clause is filed, as it's added
(`add-clause`), by the shape of its head's first argument, into a
per-predicate `pred-entry`:
- `var-clauses`: clauses whose first argument is a raw variable (`?x`) --
  these unify with *any* call, so they're always candidates.
- `keyed`: an `equal` hash table from a shape key to the clauses with that
  key -- `:cons` for any clause whose first argument is a compound/list
  term, or the argument's own literal value (numbers, symbols, `nil`, ...)
  otherwise.

At lookup time (`candidate-clauses`), a call with a *bound* first argument
only needs `var-clauses` plus whichever *one* keyed bucket matches its own
shape/value -- every other clause is guaranteed to fail unification on its
first argument alone (see the correctness argument in the comment above
`candidate-clauses` in the source; it boils down to `unify*`'s own logic:
a variable always unifies, a cons can only unify with another cons, and a
literal only unifies with something `equal` to it -- exactly the same
`equal` test `unify*` already uses). This means indexing can never change
*which* clauses succeed or their relative order, only which ones get
tried -- it is a pure speed optimization, not a behavior change. A call
whose own first argument is still unbound, or a predicate with arity 0,
falls back to trying every clause, exactly as in v2 -- indexing has
nothing to rule out in those cases.

Each clause carries a global sequence number (`clause-seq`) so that, when
both `var-clauses` and one keyed bucket contribute candidates, they can be
merged back into original declaration order cheaply (`merge-by-seq`, a
standard 2-way merge of two already-ordered lists) rather than needing a
full re-sort.

### Verification

Full regression suite (same as the v2 section) reran against the actual
deployed file with identical output to both v1 and v2. Additional
indexing-specific edge-case tests, all passing:
- An arity-0 predicate (no first argument to index on).
- A 6-fact toy database (`parent/2`): point-lookups by a bound first
  argument return exactly the matching facts, in original declaration
  order; a lookup with an unbound first argument still returns *all* 6
  facts, in original order (the fallback path).
- A predicate with declaration order literal-clause, var-clause,
  literal-clause interleaved: confirmed the *merged* candidate order
  still matches original declaration order, not insertion-into-bucket
  order.
- Cons-shaped first arguments (`nil` vs `(?h . ?t)`), including a deeply
  nested compound term, still unify correctly.
- Cut (`!`) still behaves correctly when an earlier clause is skipped
  entirely by indexing (cut-depth truncation is about the choice-point
  stack, which indexing doesn't touch).

### Performance: the payoff is at scale, not on the existing benchmarks

The three existing benchmarks (count-up3, queens, nrev) barely move,
because their predicates mostly use a *variable* in the first argument
position (the accumulator-style tail-recursion idiom this whole codebase
uses to stay heap-safe) -- indexing has little to skip there. Where it
DOES help even in the existing code: predicates using the "guard clause"
idiom with a literal first argument, e.g. `mklist(0, nil) :- !.` vs
`mklist(N, [N|T]) :- N>0, ...` (skips the wasted attempt against `0` on
every one of the many calls where N isn't 0), or `queens-safe(nil, ...)`
vs `queens-safe([Q|Qs], ...)` (every call now tries exactly one clause
instead of two). Measured effect on the 200-reps-nrev(100) benchmark:
0.93s (v2) -> 0.78s (v3); nrev(1280) alone: 1.09s -> 0.92s.

The real target, per Eduardo's stated reason for asking ("we intend to
scale the codebase"), is a *large fact database* -- many clauses of one
predicate, distinguished by a literal first argument, looked up by a
bound key. Benchmark: an `employee(Id, Dept)` database, ID 0..N-1 in
declaration order, 1000-2000 point-lookups by ID spread across the whole
range:

  N (facts)    v2 (no indexing)    v3 (indexed)
  1,000        0.084s              0.000s
  2,000        0.080s              0.000s
  4,000        0.076s              0.004s
  8,000        0.348s              0.000s
  16,000       0.804s              0.000s

v2's cost per lookup grows with N (a full linear scan of the predicate's
clause list every call: O(N) per lookup, O(N x lookups) total). v3's cost
per lookup does not grow with N at all (down in the noise of the timer's
resolution even at 16,000 facts) -- exactly the O(1)-ish-per-lookup
behavior real Prolog engines get from first-argument indexing. This is
the gap that would have mattered most as this codebase grows to hold
larger fact databases, per-Eduardo's stated reason for asking for this.

### What indexing does NOT do

- Only the *first* argument is indexed. A predicate that needs to be
  looked up efficiently by its *second* (or later) argument gets no help
  from this -- real Prolog engines sometimes also index deeper arguments;
  this implementation doesn't.
- Within the `:cons` bucket, all compound/list-shaped first arguments
  share one bucket regardless of their own functor/arity or head -- e.g.
  `f(a,b)` and `[1,2,3]` as first arguments would be in the same bucket
  (both are just Lisp conses in this s-expression-based representation,
  with no further structural indexing beyond "is a cons"). Only matters
  if a single predicate mixes many different compound shapes in its first
  argument AND that predicate also has a large clause count -- not a
  pattern in this codebase so far.
- The constant-factor gap against SWI-Prolog on count-up3/queens (the v2
  section's "bottom line") is unchanged by this -- those predicates don't
  have literal first arguments to index on, so this optimization doesn't
  touch them. What's left there is still: interpreting a copied
  S-expression per call instead of compiled code (SWI's WAM compilation),
  which would be a much larger undertaking than either of these two
  rounds of changes.

### If this needs to be revisited

- Rollback is still `~/csand/patrice-prolog` (the pre-v2 snapshot) for a
  full revert, or the v2-without-indexing state can be recovered by
  reverting just the clause-database section of this file back to a
  flat `(gethash key *database*)` list and dropping `candidate-clauses`,
  `pred-entry`, `index-key`, `head-first-arg`, and `merge-by-seq` -- the
  rest of v2 (trail-based binding, lazy clause trial) is untouched by
  this round and would keep working exactly as documented in the previous
  section.
- If a predicate ever needs indexing on a LATER argument, or needs
  indexing deeper into a compound first argument's own structure (e.g.
  by functor name, not just "is a cons"), `candidate-clauses` is the
  single place to extend -- the correctness argument in its comment
  block is the thing to re-verify carefully if it's ever generalized.

## v4: a standard-Prolog anonymous variable, _ (2026-09-14)

Eduardo's instruction: "The next step is to make ?_ act as standard
Prolog. By the way, you can change its name to _ (there is no reason to
keep the question mark in its name). Then, modify the benchmark to
reflect the new _ where it is appropriate."

### What changed

Before this, `?_` had no special meaning at all -- it was just an
ordinary named variable, like `?x` or `?result`, that happened to be
spelled with an underscore. That's a real gap from standard Prolog, where
`_` is special: EVERY occurrence of `_` denotes a DIFFERENT, unrelated
variable, even within the same clause head, unlike a named variable
(where repeated occurrences of the same name all refer to the SAME
variable). This was already a known, documented problem in this codebase
-- it's exactly the bug behind `bench_claude_prolog.lisp`'s
`?ignore1`/`?ignore2` workaround in `queens-safe`'s base case, and behind
several `?_` uses in `99/p01-p10.lisp` (harmless there only because none
of them happened to reuse `?_` twice in the same clause).

v4 gives the bare symbol `_` (no question mark) real anonymous-variable
semantics:
- `instantiate` (turns clause/query source into a term with real pvars)
  now special-cases `_`: instead of looking it up in the same-symbol-
  same-pvar table every other variable uses, it always allocates a BRAND
  NEW pvar, so `(same-q _ _)` unifies with `(same-q 1 2)` just as
  correctly as it does with `(same-q 5 5)`.
- `query-vars` (which lists a query's own variables, for printing their
  bindings) now excludes `_` -- standard Prolog never prints a binding
  for the anonymous variable, and there's no single binding to print for
  it anyway, since every occurrence is independent.
- Clause indexing (v3) treats `_` exactly like any other variable: a
  wildcard that matches any call, always a candidate. No change needed
  there beyond broadening the existing "is this source syntax for a
  variable" check to include `_`.

`?_` (with the question mark) is UNCHANGED -- it's still just an ordinary
named variable, so old code that uses it keeps working exactly as it did
before. There's just no longer any reason to spell it that way, since `_`
now does the job properly.

### Verification

Full regression suite (same as the v2/v3 sections) reran against the
actual deployed file with identical output. Additional tests specific to
this change, all passing:
- Two `_` in one clause head genuinely don't alias: `(same-q _ _)` with
  `(same-q 1 2)` (different values) succeeds, where the old `?_` would
  have wrongly forced `1` to unify with `2` and failed.
- The exact motivating case -- `queens-safe`'s base case, now written
  `(queens-safe nil _ _)` instead of `(queens-safe nil ?ignore1
  ?ignore2)` -- correctly validates a real 8-queens solution.
- `_` used 4 times in one clause head, all independent.
- `_` in a QUERY (not just a clause head) is correctly excluded from the
  printed bindings, including with multiple `_`'s in the same query.
- `?_` (old spelling, question mark kept) still behaves exactly as
  before -- an ordinary named variable, so writing it twice still
  (correctly, unsurprisingly) forces its two occurrences to unify. No
  regression for any existing file that already used `?_` this way.
- `_` as a clause's first argument still gets indexed as a wildcard
  (both the `_`-headed clause and a literal-headed clause on the same
  predicate are correctly offered as candidates, in declaration order).

No measurable performance change (expected -- this adds one cheap check
on an already-hot path, not a new pass over anything): consed-byte counts
on the queens/nrev benchmarks are within noise of the v3 numbers.

### The benchmark file had a separate, pre-existing bug -- now fixed

While updating `bench/bench_claude_prolog.lisp` for the `_` change, I
found it had been silently broken since the v2 rewrite (the previous
session): `count-all-solutions` and the nrev-scaling loop still called
`ground`/`solve-one`/`solve-next` using the OLD v1 API (a bindings alist
passed around, e.g. `(ground '?list bindings)`), which v2 changed to
`protected-vars` (see the "v2 rewrite" section above). Benchmark 1
(`count-up3`) happened to keep working, since it only goes through the
`?-` macro, which didn't change -- but Benchmark 2 (nrev) crashed
outright with `invalid number of arguments: 2` on `ground`, and would
have crashed anyone who tried to rerun this file since the v2 rewrite.
This has been fixed (both spots now use the current `(values protected-
vars choices ok)` API, matching the style already used in `nrev-scaling-
v2.lisp` and `queens8-v2.lisp` during that rewrite's own testing) and the
whole file re-verified end to end against the actual deployed engine --
all three benchmarks now run cleanly again. `bench_swi.pl` needed no
changes (it never touched claude-prolog's internal API).

### If this needs to be revisited

- `anonymous-var-p` (checks for the exact bare symbol `_`) is the single
  place this feature is defined; `raw-var-symbol-p` was broadened to call
  it, so every existing "is this a variable" check downstream (indexing,
  instantiate, query-vars) picked it up for free.
- `99/p01-p10.lisp` still has several `?_` uses (P01, P02, P03, P04) that
  were never bugs (each is used only once per clause) but could be
  updated to `_` for consistency/idiom if that's ever wanted -- left
  alone here since it wasn't part of what was asked this round.
- Rollback: `~/csand/patrice-prolog` for a full revert to before any of
  v2/v3/v4; or drop just `anonymous-var-p` and revert `raw-var-symbol-p`/
  `instantiate`/`query-vars` to their v3 form to undo only this round
  (the clause-indexing and trail-based-binding work from v2/v3 would be
  untouched by that).

## v5: a correctness bug in cut, found while looking for more optimizations (2026-09-14)

Eduardo's question: "Are there any other optimizations left in the Prolog
interpreter? If not, you can start transforming it into a compiler."

Looking for more optimizations turned up something more serious: a
pre-existing CORRECTNESS bug in how `!` (cut) truncates choice points, not
just a performance issue. It's fixed now; see below. This delayed starting
the compiler, since building one on top of buggy cut semantics would just
have propagated the bug into more code.

### The bug

Choice points are stored newest-first: each predicate call that has more
untried clauses pushes a new choice point onto the front of the list. When
a clause runs `!`, it's rewritten at clause-selection time to `(:cut
cut-depth)`, where `cut-depth` is the length of the choice-point list as it
stood at clause entry (before that clause's own body runs). The correct
meaning of cut is: discard every choice point created SINCE clause entry
(this clause's own sibling-clause choice point, plus any pushed by body
goals executed before the cut) while keeping every OLDER (ancestor) choice
point untouched. Since the list is newest-first, "keep the oldest `depth`
entries" means keeping the TAIL of the list, i.e. `(nthcdr (- current-
length depth) choices)`.

The code instead did `(subseq choices 0 depth)` -- the FIRST `depth`
entries, i.e. the NEWEST ones. That's backwards: it keeps recently-created
choice points (which cut is supposed to discard) and discards the actual
ancestor choice points cut is supposed to protect.

This only happens to give the right answer when `!` is the very first goal
in the clause body, so no choice points have accumulated since clause
entry -- then current-length == depth and "first N" and "last N" of an
N-length list are the same list, masking the bug. It gives the WRONG
answer whenever a real ancestor choice point exists on the stack AND some
body goal before the cut creates its own additional choice point(s) --
exactly the queens-safe / nrev / any-real-program shape.

Worked example that exposes it:
```
outer_choice(1). outer_choice(2).
choice2(a). choice2(b). choice2(c).
test2(O, X) :- choice2(X), !.
?- outer_choice(O), test2(O, X).
```
Correct answer (verified against real SWI-Prolog): exactly 2 solutions,
`O=1,X=a` and `O=2,X=a` -- `choice2`'s own choice point (b, c) is cut away
each time, but `outer_choice`'s ancestor choice point survives so
backtracking into it on the next call still works. With the old code this
produced 4 wrong answers (it also incorrectly cut away `outer_choice`'s
own alternatives in some paths and left `choice2`'s in others).

### Provenance: this predates the whole project

`grep` on `~/csand/patrice-prolog/prolog-engine.lisp` (the original v1
code Eduardo provided, kept untouched as the project's rollback point)
shows the identical `(subseq choices 0 depth)` at line 153. This bug was
never introduced by the v2 trail-based rewrite, v3 indexing, or v4
anonymous-variable work -- it's been there since before this project
started, just masked in every test/benchmark that happened to put `!`
first in the body (which is most of them -- it's a common style).

### The fix, plus a bundled O(1) optimization

Fixed the truncation direction: `(nthcdr (- (choices-depth choices) depth)
choices)`. While in there, also fixed a real independent performance
issue: the code computed `cut-depth` at every single predicate call via
`(length choices)`, an O(depth) walk repeated on EVERY goal in the program
(not just ones using cut). Added a `depth` slot to the `choice` struct,
set once at creation time in `try-clauses` as `(1+ (choices-depth outer-
choices))`, and a `choices-depth` helper that reads it in O(1) off the top
choice point (`(if choices (choice-depth (car choices)) 0)`, declaimed
inline). `solve-from` and `try-clauses` both now use this O(1) read
instead of `length`.

### Verification

- The worked example above: now gives exactly the 2 correct answers,
  matching real SWI-Prolog run on the equivalent program.
- A triple-nested variant (outer choice point, middle clause with its own
  choice point + cut, inner clause with its own choice point + cut):
  correctly gives 2 answers.
- The original masked case (cut first in body, depth==current-length):
  still correct, unaffected by the fix, confirming no regression in the
  common case.
- Full regression suite (1prolog-test through p01-p10, same as v2/v3/v4):
  identical output, re-run against the actual deployed engine file.
- Full v4 anonymous-variable test suite: all still pass.
- `queens8` (expect 92 solutions): still 92, and now measurably cheaper --
  758M bytes consed vs. ~850-856M before the fix. The bug was also
  silently causing wasted backtracking work elsewhere in the search tree
  (failing to prune branches cut should have removed), so fixing
  correctness incidentally improved performance too.
- `nrev` scaling and `bench/bench_claude_prolog.lisp` (all 3 benchmarks):
  unaffected, still correct, re-run end to end against the deployed
  engine.
- All of the above re-verified twice: once against the sandbox copy used
  to develop the fix, and again after deployment, against the actual file
  staged fresh from `~/csand/claude-prolog/prolog-engine.lisp` (md5sum-
  matched to the sandbox copy) -- the same rigor applied to v2/v3/v4.

### Other things looked at, not changed

While answering "are there other optimizations left," two small items were
also identified but left alone, since they're either superseded by or
better addressed inside the compiler work started next:
- `predicate-key` allocates a fresh cons per goal dispatch, just to use as
  a hash-table key. Minor and orthogonal to the compiler; could be
  revisited later (e.g. an `equal`-hashed struct or a string key) if it
  ever shows up in a profile.
- Goal-list splicing (appending a clause's instantiated body onto the
  remaining goals) copies the tail list on every clause entry. Also
  minor.
The two big remaining costs -- reconstructing a clause's body from scratch
via `instantiate` on every entry, and generic runtime-dispatched `unify*`
-- are exactly what compiling each clause into a specialized Lisp closure
is meant to eliminate, which is the direction taken next per Eduardo's
"specialized unification for each predicate" suggestion.

### If this needs to be revisited

- The `choice` struct's `depth` slot and `choices-depth` are the only new
  state; `builtin-step`'s `:cut` case and `try-clauses`'s choice creation
  are the only two call sites that needed the direction fix.
- Rollback: `~/csand/patrice-prolog` for a full revert to before any of
  v2-v5 (note this rollback point still HAS the cut bug); or revert just
  the `:cut` case in `builtin-step` back to `subseq` and drop the `depth`
  slot/`choices-depth` helper to undo only this round.

## v6: a clause COMPILER, not just an interpreter (2026-09-14)

Eduardo's instruction: "Are there any other optimizations left in the
Prolog interpreter? If not, you can start transforming it into a
compiler. I believe there are two kinds of predicates: those defined in
Prolog and primitive predicates that are Lisp calls. Compilation is
transforming Prolog-defined predicates into Lisp calls. One approach to
compilation is to create specialized unification for each predicate."

The answer to the first half was "one real thing" -- the v5 cut bug,
already covered in its own section above. Beyond that, the two
remaining interpreter-level costs (rebuilding a clause's whole body via
INSTANTIATE on every attempt, and generic runtime-dispatched UNIFY*) are
exactly what compiling is meant to eliminate, so that's the direction
taken here, exactly as suggested: specialized head-matching per clause.

### What "compiling a clause" means here

Through v5, EVERY attempt to match a call against a clause did two full
generic passes: INSTANTIATE walked the clause's raw source (head AND
body), replacing every `?xxx` with a fresh pvar via a fresh EQ hash
table (so repeats share one pvar) -- building the clause's ENTIRE term
structure from scratch, unconditionally, even for a clause whose head
was obviously never going to match; then generic UNIFY* walked the
freshly-built head against the call, cons cell by cons cell, working out
at runtime facts about the clause's own shape (is this position a
variable? a literal? does it repeat?) that were already fully known the
moment the clause was asserted.

v6's COMPILE-CLAUSE does that analysis ONCE per clause and emits actual
Lisp source implementing exactly that one clause's head match and body
construction, handed to SBCL's own compiler (`(compile nil ...)`) to
become a real native closure: `(funcall matcher call-args cut-depth) =>
(values matched-p fresh-body)`. The generated closure:
- never builds the clause's head as a term at all -- it matches the
  call's actual runtime arguments directly, position by position;
- calls `bind-var` (an unconditional bind) exactly where the clause is
  STATICALLY known to be touching a variable for the first time anywhere
  in that clause, and falls back to full `unify*` only where a variable
  is statically known to repeat -- the compile-time analysis behind this
  (and the one subtlety in it: an occurrence embedded inside another
  argument's freshly-built substructure does NOT count as "touched",
  since embedding a still-unbound cell isn't the same as binding it) is
  written up in detail in COMPILE-HEAD-MATCH's docstring in the engine
  file itself;
- needs no per-attempt hash table at all -- each of the clause's
  distinct named variables gets exactly one lexical Lisp variable,
  allocated once via a `let` at the top of the generated closure, so
  sharing between repeated occurrences (head-to-head, head-to-body, or
  within the body) falls out of ordinary Lisp lexical scoping for free;
- builds the fresh body directly via nested `cons`/`make-pvar` forms,
  with `!` compiled straight to `(:cut cut-depth)` -- replacing both
  INSTANTIATE's generic tree-walk over the body AND the separate
  REWRITE-CUTS pass that used to follow it.

TRY-CLAUSES now calls the clause's compiled matcher instead of
INSTANTIATE+UNIFY*+REWRITE-CUTS. Nothing else changed: indexing (v3),
the trail (v2), backtracking, and cut EXECUTION itself (BUILTIN-STEP's
`:cut` case, v5) are all exactly as before -- the compiler only changes
*how a clause's own match gets computed*, not any of the surrounding
control machinery.

Queries are NOT compiled -- a query only ever runs once, so there's
nothing to amortize a compile against; INSTANTIATE remains exactly what
it always was for that one remaining use. And PRIMITIVE predicates
(`:cut`, `unify`, `lisp-eval`, `is`, the comparisons) were already direct
Lisp dispatch via BUILTIN-STEP -- there was nothing to compile there in
the first place; only PROLOG-DEFINED predicates (added via `<-`) go
through COMPILE-CLAUSE.

### Compilation is LAZY, not eager -- and why that matters

The first version of this compiled every clause at ADD-CLAUSE (assert)
time. That turned out to be a real mistake for one important case: a
LARGE static fact database. Compiling calls SBCL's actual compiler,
which costs real (sub-millisecond, but non-trivial) time per clause --
fine when amortized over many calls to a handful of clauses (a recursive
helper predicate like `myapp`, called thousands of times over just 2
clauses), but not fine for, say, 16,000 ground facts loaded once and
queried sparsely. Measured: eagerly compiling all 16,000 up front cost
~5.3s just to load them, versus ~0.35s pre-compiler (v5) -- a real,
unnecessary regression for exactly the large-fact-database scaling use
case v3's indexing work was aimed at.

Fixed by making compilation LAZY: a clause's `matcher` slot starts NIL,
and CLAUSE-MATCHER! compiles it (once) the first time it's actually
offered as a match candidate in TRY-CLAUSES, caching the result from
then on. This makes ADD-CLAUSE cheap again (back to being an O(1)
hash/list insert, exactly as in v2-v5) and spends the compile cost only
on clauses actually visited while solving. Measured, loading 16,000
facts: back down to ~0.36-0.5s (matching v5), with the compile cost that
used to be paid at load time now paid the first time each fact is
actually looked up (visible as the LOOKUP phase of the same benchmark
costing ~0.3-0.45s instead of ~0.0000s, for a workload that happens to
touch ~1000 distinct facts out of the 16,000 -- see "An honest tradeoff"
below).

### Verification

Same rigor as v2-v5: the full regression suite (1prolog-test through
p01-p10), the v5 cut-bug regression tests (including the triple-nested
variant), and the full v4 anonymous-variable test suite all re-run
against BOTH the sandbox copy used to develop this and, separately, the
actual file staged fresh from the deployed
`~/csand/claude-prolog/prolog-engine.lisp` (md5sum-matched) -- byte-for-
byte identical output to v5 in every case, including the exact `!`
scenario that exposed the v5 cut bug (now routed through a compiled
clause instead of an interpreted one, still correct).

New COMPILER-SPECIFIC tests were added and pass (also byte-identical on
sandbox vs. deployed-and-staged), targeting the actual subtleties in
COMPILE-HEAD-MATCH's design:
- a variable repeated across two TOP-LEVEL head positions (`(foo ?x
  ?x)`), forcing them equal;
- a variable that first appears EMBEDDED inside another argument's
  cons pattern (so it must NOT be marked "touched"), with a second,
  literal top-level occurrence later in the same head -- and the
  reverse ordering;
- a variable repeated TWICE within one single cons pattern (`(foo (?x .
  ?x))`);
- a deeply nested cons pattern mixing literals and variables several
  levels down;
- the anonymous variable `_` nested inside a cons pattern, alongside
  named variables (still correctly excluded from any printed binding,
  still correctly independent per occurrence);
- literal head arguments (numbers, symbols, `nil`) mixed with variables;
- a variable used only in the BODY, never in the head;
- the exact v5 cut-bug shape (an ancestor choice point plus a body goal
  before `!` that creates its own choice point), now running through a
  compiled clause -- still exactly 2 answers;
- indexing interacting correctly with compiled matchers across multiple
  clauses of one predicate, including a var-clause fallback;
- `*occurs-check*` still working correctly through a compiled matcher's
  `bind-var` calls, including the "embedded, still-unbound" case;
- real backtracking through a compiled clause with its own choice point
  (a compiled `my-select`-style predicate), enumerating all 3 answers.

All benchmarks re-run (sandbox and staged-deployed, identical results):
- The 1,000,000-step `count-up3` loop: 2.42s / 1.95GB consed (v5) down
  to ~0.47-0.6s / ~893MB consed (v6) -- roughly 4x faster, more than 2x
  less consing.
- `queens8` (92 solutions): 1.18s / 758MB consed (v5) down to
  ~0.25-0.28s / ~356MB consed (v6) -- roughly 4.5x faster.
- `nrev(100)` x200 reps: 1.01s / 870MB consed (v5) down to ~0.24s /
  328MB consed (v6) -- roughly 4.2x faster.
- `bench/bench_claude_prolog.lisp` (all 3 benchmarks, unmodified): same
  improvements, no changes needed to the file itself.

### An honest tradeoff: compiling costs something the interpreter didn't

Even with laziness, compiling isn't free, and there's one workload shape
where v6 is NOT a clear win over v5: a large fact table queried
SPARSELY, where most touched facts are looked up only once or twice per
program run. First-argument indexing (v3) already means a bound-key
lookup only ever visits ONE clause; for a plain ground fact with no
repeated variables, generic INSTANTIATE+UNIFY* was already cheap, so
paying a one-time SBCL-compile cost to build a specialized matcher for a
clause that's then used exactly once is a net loss for THAT clause,
even though it's a clear win (and pays for itself almost immediately)
for anything called more than a couple of times -- which describes most
recursive predicates in real programs. This is an inherent property of
compiling at all (lazy or eager), not a defect specific to this
implementation -- real compiled Prolog systems make the same tradeoff at
consult/assert time. It's flagged here rather than hidden because it's
the one case in this whole project where v6 can, for a specific query
pattern, be measurably slower in total wall-clock than v5's plain
interpretation -- worth knowing if a future workload leans heavily
towards "assert a huge table, touch each fact once."

### If this needs to be revisited

- COMPILE-CLAUSE, COMPILE-HEAD-MATCH, COMPILE-FRESH-TERM, and COLLECT-
  CLAUSE-VARS are the whole compiler; TRY-CLAUSES's use of CLAUSE-
  MATCHER! is the only call site that changed to use it. INSTANTIATE is
  untouched and still used for queries.
- If the "touch each fact once" cost ever matters in practice, a
  reasonable next step would be to skip compiling (fall back to
  INSTANTIATE+UNIFY*) for a clause identified as a pure ground fact --
  empty body, no variables at all in the head -- since compiling buys
  essentially nothing there; not implemented here since it wasn't
  reported as an actual bottleneck, just measured and noted.
- Rollback: `~/csand/patrice-prolog` for a full revert to before any of
  v2-v6; or drop this section's changes specifically by reverting
  TRY-CLAUSES to call INSTANTIATE+UNIFY*+REWRITE-CUTS again (its v5 form
  is preserved in git history / prior NOTES.md sections) and removing
  the MATCHER slot -- v2-v5's indexing, trail, and cut-fix work would be
  completely unaffected by that.

## Prototype: mode-declared deterministic predicates -> direct Lisp functions (2026-09-14)

Eduardo's idea, from his own past Prolog-in-Lisp implementation: a
deterministic predicate with a MODE declaration (which argument positions
are inputs, bound at call time, and which are outputs, produced by the
call) can compile directly into a Lisp function that takes the inputs as
plain arguments and returns the outputs via `(values ...)` -- no pvars,
no trail, no unification, no choice points at all, just ordinary Lisp
function application. This is strictly stronger than v6's per-clause
compiler (which still allocates pvars and calls `bind-var`/`unify*` for
generality, since it has to stay correct for nondeterministic and
partially-instantiated calls too).

This is a PROTOTYPE, in a new file `mode-compiler.lisp` (load AFTER
`prolog-engine.lisp`), not merged into the deployed engine -- it doesn't
touch `prolog-engine.lisp` at all, it's purely additive. `<-` is
completely unchanged; `mode-compiler.lisp` just reads a predicate's
already-asserted clauses out of the normal `*database*` and compiles
them differently, once, when you declare `(mode (pred-name m1 ...))`
(one `+`/`-` per argument position) after asserting all of that
predicate's clauses via `<-` as usual. It generates a genuine native
Lisp function `MODED-<PRED>-<ARITY>`, callable directly.

### Correctness

Eight test groups, all passing: the moded `count-up3` cross-checked
against the ordinary interpreted engine on the same query; a literal
output pattern (a fixed atom, not a computed variable); a repeated
input variable (forcing an equality check between two `+` positions);
`_` in an input position; two arithmetic steps producing two separate
outputs from one clause; and three deliberate error cases (a compound
pattern in a `+` position, a moded call that isn't the last goal in its
clause body, and a call to a predicate with no `mode` declaration) --
each correctly rejected at compile time with a clear message rather
than silently miscompiled.

### The headline number

`count-up3`, the exact 1,000,000-step benchmark used throughout this
whole project:
- v6 (general engine, compiled clauses): 0.59s, 893MB consed.
- moded, direct Lisp function call: **0.008-0.016s, ZERO bytes consed.**
- SWI-Prolog, same benchmark: 0.19-0.22s CPU.

The moded version is roughly **40-70x faster than v6's general engine**,
and roughly **15-20x faster than SWI-Prolog itself**. Zero consing
because, once compiled, this really is just a tail-recursive Lisp
function doing floating-point arithmetic and comparisons -- nothing
about it differs from what a human would hand-write. Confirmed the
1,000,000-deep self-recursion (`count-up3` calling itself once per
0.01-increment) does NOT blow the stack -- SBCL genuinely tail-call-
optimizes the generated code, verified empirically (not just assumed),
since that was the one real risk in this design: if SBCL hadn't TCO'd
it, this would have crashed instead of running in 8ms.

SWI is a mature, decades-old engine that ALSO does real unification,
indexing, and choice-point management even for a predicate that happens
to be deterministic -- it isn't leaving this kind of performance on the
table by mistake, it's paying for generality this specific technique
opts out of entirely for the cases it applies to. The comparison is
worth having precisely because it shows what's possible once a human
(or a mode declaration) asserts "trust me, this predicate is
deterministic and I'm telling you exactly which arguments are inputs" --
information a general resolution engine has to work harder to prove or
discover on its own.

### How it works

Each clause of a moded predicate compiles to one `cond` clause in a
single generated function: the `+` positions' patterns become guard
checks (literal equality, or an `equal` check when the same variable
name repeats across two `+` positions; a bare variable with no repeat
needs no check at all, since it's just naming the function's own
parameter) folded into the `cond` test, and everything after becomes
the clause's consequent, built as `let*` bindings from `lisp-eval`/`is`/
`unify` steps that define an output variable, ending in either
`(values t out1 out2 ...)` or, when the clause's LAST goal is a call to
ANOTHER moded predicate whose own outputs map directly onto this
clause's outputs, a literal Lisp tail call to that predicate's generated
function -- this is the shape that made `count-up3`'s self-recursion
into a genuine Lisp tail call. `!` is simply a no-op in this compiled
form, since clause selection here is exactly `cond` -- there's no
choice-point stack to cut, because there's no backtracking machinery
here at all.

### Scope of this prototype -- restrictions, all enforced at compile
### time with a clear error, none silently mishandled

- A `+` (input) position's pattern may be a bare variable, `_`, or a
  literal -- not a compound (cons) pattern. (Matching a cons pattern
  against a known-ground input is easy in principle, the same
  `consp`+recurse approach v6's `compile-head-match` uses minus the
  pvar branch -- it just wasn't needed to answer the speed question, so
  it's flagged rather than attempted.)
- A `-` (output) position's pattern must be a bare variable or a
  literal, not a compound pattern -- build compound output structure
  via a body `unify` into a bare output variable instead.
- Every predicate CALLED from a moded clause's body must itself be
  moded; there's no fallback to the general engine mid-clause.
- A moded call may appear ONLY as the clause's last goal, with its
  outputs lining up with the clause's own outputs in order -- this is
  specifically what makes self/mutual recursion compile to a real Lisp
  tail call. A moded call anywhere else (feeding further computation,
  or with more goals after it) isn't supported yet.
- Supported body vocabulary otherwise: `!` (no-op), `lisp-eval`/`is`
  (a boolean guard, an output definition, or an equality check),
  `unify` (same three shapes), and the direct comparison builtins.

None of this touches the deployed `prolog-engine.lisp` -- a predicate
can be asserted via `<-` and used exactly as before (interpreted/v6-
compiled, nondeterministic, partially instantiated, all of it) whether
or not it also happens to have a `mode` declaration and a compiled
direct-call twin sitting alongside it.

### If this goes further

The natural next step, if this is worth promoting from prototype to a
real engine feature, is wiring moded-predicate calls into v6's ORDINARY
clause compiler too: when an ordinary (unmoded) clause's body calls a
predicate that turns out to have a `mode` declaration, `compile-clause`
could emit a direct call to its `MODED-...` function (grounding the `+`
argument expressions, `unify*`-ing the `-` argument expressions against
the returned values) instead of going through the general `candidate-
clauses`/`try-clauses` path for that one goal -- letting ordinary
nondeterministic Prolog code get this speedup for the deterministic
helper predicates it calls, without having to be moded itself. That's a
real integration project (correctly interleaving grounding/unification
at the call boundary, deciding what happens if a `+` argument isn't
actually ground at that point despite the mode's promise, etc.), not
attempted here -- this prototype answers "does the technique work and
how fast is it," which was the question asked.

### Addendum: verified for more than two output values (2026-09-14)

Eduardo asked specifically whether more than one output value was
tested -- two, three, or four -- and asked for `multiple-value-bind` as
the verification idiom rather than `multiple-value-list`. It hadn't
been (the correctness tests above only went up to two outputs, via
`minmax`, checked with `multiple-value-list`). Added `mode-multivalue-
tests.lisp`, all via `multiple-value-bind`:
- three outputs (`triple`, one arithmetic step per output) -- correct,
  and cross-checked against the ordinary interpreted engine on the
  same query, matching exactly;
- four outputs (`quad`, mixing `unify` and `lisp-eval` to define each
  one);
- a two-clause moded predicate with three outputs each (`triple2`),
  confirming clause SELECTION still picks the right clause and returns
  the right value count/values from either one;
- two more predicates (`relay`/`relay4`) that TAIL-CALL `triple`/`quad`
  as their own last goal, confirming the multi-output TAIL-CALL path
  (not just the direct-return path) correctly threads three and four
  values through unchanged.

All ten `multiple-value-bind` checks passed. The arity handling in
`compile-det-predicate`/`compile-det-clause` was already fully general
(it loops over the mode list, not special-cased to any particular
count), so this wasn't expected to surprise -- but it hadn't actually
been exercised beyond two before, and is now.

## Fortran-style inline mode syntax (2026-09-14)

Eduardo: "I noticed that you used mode declaration after the clauses (or
before, I am not sure). However, we could act like Fortran: output
variables would start with +, input variables would start with -, and
two way variables would be a question mark. +x is output, -x is input
and ?x is logic variable."

Instead of writing a clause with ordinary `?`-variables and then a
separate `(mode (pred + - ...))` declaration afterward, a clause head can
now name its own mode directly in its variable spelling:

```lisp
(<- (count-up3 +n +stop -out)
    (lisp-eval t (>= ?n ?stop))
    !
    (unify ?out ?n))
(<- (count-up3 +n +stop -out)
    (lisp-eval ?next (+ ?n 0.01))
    (count-up3 ?next ?stop ?out))
;; no (mode ...) call needed -- MODED-COUNT-UP3-3 already exists here.
```

Scope, confirmed with Eduardo before implementing:
- The `+`/`-` annotation applies to **head arguments only**. Body
  variables are unaffected and stay ordinary `?x` syntax -- once a head
  variable's mode is declared inline, every later mention of that same
  variable (in the head or the body) is written the ordinary `?`-prefixed
  way, exactly as `count-up3`'s body above writes `?n`/`?stop`/`?out`,
  not `+n`/`+stop`/`-out`, once past the head.
- If a clause head **mixes** `+`/`-` annotated variables with a bare
  `?x` logic variable, that's a compile-time **error**, not a silent
  fallback -- annotate every variable position in a head, or none.

### One polarity, not two

Eduardo's first description of the syntax used the Fortran convention
above (`+` = output, `-` = input), which is the *opposite* of this
project's existing explicit `mode` macro (`+` = input, `-` = output --
inherited from Eduardo's original mode-declaration description,
"...put the output variables together at the end", and baked into every
function/variable name in `mode-compiler.lisp`: `*det-modes*`,
`compile-det-clause`'s `(eq m '+)` branches, etc). The first
implementation of this section kept both conventions side by side, with
a translation function between them -- Eduardo caught that this was the
wrong call ("Both should [not] coexist. Use your polarity") and it's
fixed now: the inline syntax uses the *same* convention as `mode`,
`+` = input, `-` = output, throughout. There is exactly one polarity in
`mode-compiler.lisp`; nothing translates between two anymore.

The Lisp reader resolves the one syntactic question this raised for
free: `-5` and `+5` read as **numbers**, not symbols, so a literal input
or output like `-5` in a head position is never mistaken for an
annotated variable -- `moded-var-p` starts with a `symbolp` check, which
numbers simply fail.

### How it's implemented

- `moded-var-p` recognizes an inline-annotated variable: a symbol whose
  name starts with `+` or `-` and has at least one more character.
- `moded-var-canonical` strips the prefix and returns the ordinary
  `?`-spelled symbol (`+OUT` -> `?OUT`), so the clause, once stored, is
  byte-for-byte indistinguishable from one written with plain `?`-syntax
  throughout -- the general engine, v6's per-clause compiler, and
  first-argument indexing don't need to know this syntax exists at all.
- `strip-moded-head` walks a clause head once: if no argument is
  annotated, the head passes through completely untouched (an ordinary
  clause costs nothing extra). If any argument is annotated, every
  *variable* argument must be (a bare `?x` triggers the mixing error
  above); non-variable positions (a literal, or `_`) may appear freely,
  since they have no prefix to annotate in the first place. Returns the
  stripped, canonical-`?`-form head plus a per-position mode list, in the
  same convention as the explicit `mode` macro (`+`/`-` for an annotated
  position, `NIL` for a literal or `_` position -- see below).
- `<-` itself is redefined (shadowing the original from
  `prolog-engine.lisp`; `mode-compiler.lisp` loads after it) to call
  `strip-moded-head` on the head **at macroexpansion time** (the head is
  a literal form, never evaluated, so this costs nothing at runtime). A
  clause with no inline annotation expands to exactly the same
  `(add-clause ',head ',body)` the original macro produced -- ordinary
  clauses are completely unaffected, verified with a sanity check
  (`append2`, no annotation at all) run after loading `mode-compiler.lisp`.
  An annotated clause instead expands to a call to `register-moded-clause`.
- `register-moded-clause` asserts the (already-canonical) clause via the
  ordinary `add-clause` -- so the predicate remains fully usable the
  ordinary interpreted/v6-compiled way regardless of what happens next --
  then merges this clause's per-position modes into a new
  `*det-mode-progress*` table (`PRED.ARITY -> modes so far`, via
  `merge-det-modes`) and, once **every** argument position has a
  resolved (non-`NIL`) direction, automatically calls
  `compile-det-predicate` to (re)generate `MODED-<PRED>-<ARITY>` -- no
  explicit `(mode ...)` call needed for a predicate defined entirely
  with inline syntax. Each new clause simply retriggers a fresh recompile
  against the full clause set asserted so far.

### The literal/`_`-position limitation

A literal (or `_`) head position carries no `+`/`-` prefix to read, so
its direction can't be inferred from inline syntax alone -- exactly the
`parity` example from the prototype above, where the second position is
always a fixed atom (`even`/`odd`), never a variable, in *every* clause.
`*det-mode-progress*` for such a predicate is left permanently holding a
`NIL` in that position (`merge-det-modes` only ever resolves a `NIL` to
a real direction, never manufactures one out of nothing), so it never
auto-compiles via inline syntax alone. This is a known, documented
limitation, not a bug: the clauses are still fully usable the ordinary
way, and the explicit `mode` macro remains a working manual fallback for
exactly this case -- it works unmodified on inline-declared clauses too,
since the stored clause is plain `?`-syntax underneath either way.

### Conflicting directions across clauses

Two clauses of the same predicate giving *opposite* inline directions
for the same argument position (one says `-x` there, another says `+x`)
is a clear compile-time error from `merge-det-modes`, not silently
resolved either way.

### Testing

`fortran-mode-tests.lisp`, all passing, verified against the actual
staged device copy of `mode-compiler.lisp` (rewritten once, after the
polarity fix above, to use the corrected `+`=input/`-`=output
annotations throughout -- `count-up3f(+n +stop -out)`, `triplef(+a -x -y
-z)`, etc):
- `count-up3` rewritten with inline syntax and **no** explicit `mode`
  call at all, cross-checked against the interpreted engine, both as a
  direct call and via an ordinary `?-all` query (proving the stripped
  clause really is usable the general way too);
- the same 1,000,000-deep stack-safety/TCO check as the explicit-mode
  version, and a head-to-head `time` comparison confirming identical
  performance (single-digit-milliseconds/0 bytes consed either way --
  expected, since both mechanisms share the same `compile-det-clause`/
  `compile-det-predicate` machinery; only the front-end syntax differs);
- the 3-output/4-output/tail-call-chaining multi-value predicates
  (`triplef`, `quadf`, `relayf`) rewritten with inline syntax, verified
  via `multiple-value-bind`, matching the explicit-mode versions;
- `_` in a head position, confirmed to NOT auto-compile (the
  literal/`_`-position limitation above) and to work via the explicit
  `mode` fallback;
- the mixing error (`-x ?y +z`) and the conflicting-direction error
  (one clause says `-y`, another says `+y`, same position) both
  correctly rejected with clear messages;
- the literal-position limitation itself (`parityf`, mirroring the
  original `parity` test), confirmed to leave `MODED-PARITYF-2` unbound
  until the explicit `mode` fallback is used.
- a standalone sanity check confirming ordinary `<-` clauses with no
  annotation at all (`append2`) still work exactly as before, after
  `mode-compiler.lisp`'s redefinition of `<-` is loaded.

### Still just a prototype

Same caveat as the mode-declared prototype above: `mode-compiler.lisp`
is loaded *after* `prolog-engine.lisp` and never modifies it --
`prolog-engine.lisp`'s own md5sum is unchanged by this work. Everything
here (both the explicit `mode` macro and the new inline syntax) is an
additive front end over the same `compile-det-clause`/`compile-det-
predicate` machinery from the mode-declared-predicates prototype above;
neither is merged into the deployed engine or its ordinary compiler.

## Compound (list) patterns in moded clauses -- lists, and APPEND (2026-09-14)

Eduardo: "By the way, I am not sure whether you tested mode with list.
In case of list, if I remember well, input variables were selected and
had their structure tested with car, cdr, while output variables were
built with cons." Then, once that first idiom was working: "A good test
with list would be `(append (+x . +xs) +y (-x . -z))`" -- a compound
(cons) pattern with mode annotation nested INSIDE it, at both a + and a
- position. This is `6sum.lisp`, and it needed two genuinely different
things, not one:

### Part 1: CAR/CDR/CONS inside the body -- no new compiler support needed

Eduardo's remembered idiom works as-is, because an input argument is
already fully bound by the time a moded clause's body runs: read its
structure with ordinary Lisp `CAR`/`CDR` calls inside `LISP-EVAL`/`IS`,
build a fresh output structure the same way with `CONS`. `CAR`/`CDR`/
`CONS` aren't in `*LISP-EVAL-FUNCTIONS*` by default (arithmetic only),
but they're ordinary Lisp functions, so the EXISTING `(callable ...)`
macro (`prolog-engine.lisp`, predating this whole mode-compiler
project) registers them like any other -- and since `*LISP-EVAL-
FUNCTIONS*` is shared, both the general interpreted engine's own
`LISP-EVAL`/`IS` and the mode-compiler's `TRANSLATE-DET-EXPR` pick them
up automatically, nothing extra to wire up. `listsum` (sums a list,
accumulator-passed, genuine tail recursion) and `doubled` (doubles each
element, built via an accumulator + a final `REVERSE`, also genuine
tail recursion) in `6sum.lisp` are this idiom, both cross-checked
against the interpreted engine (see the `eval-prolog-form` rough edge
below for why that cross-check needed its own small ordinary-Prolog
helper predicate rather than calling the CAR/CDR-based definitions
directly through `?-`).

### Part 2: real compound HEAD patterns -- this needed new compiler work

Until this section, a moded clause's head positions could only be a
bare variable, `_`, or a literal -- a compound (cons) pattern in EITHER
a `+` or a `-` position was a flat compile-time error (`mode-tests.
lisp`'s old "badcons" case, kept but repurposed as a positive test now
that it's supported: it's renamed `firstof`). Eduardo's `append` example
needed that restriction actually lifted, not routed around.

**`+` (input) side** -- `MATCH-IN-PATTERN` in `COMPILE-DET-CLAUSE`
(`mode-compiler.lisp`): a compound pattern's value is already fully
bound, so it's matched by recursively destructuring with `CAR`/`CDR`,
guarded by a `CONSP` check at every level (so calling it with a non-
list correctly FAILS -- returns `(values nil)` -- instead of signalling
a raw Lisp error from `CAR`/`CDR` on the wrong kind of value). A bare
variable inside the pattern behaves exactly like a bare variable in a
flat `+` position always has: first occurrence binds it (to the
appropriate `CAR`/`CDR` chain expression), a repeat pushes an equality
guard.

**`-` (output) side** -- `BUILD-OUT-TEMPLATE`: a compound pattern
builds an output TEMPLATE (a tree mirroring the pattern's own cons
shape) rather than a single Lisp expression right away, because a
compound output can contain a mix of leaves that are already resolvable
(a bare variable that already has a binding -- APPEND's `X`, shared
between position 1 and position 3 once both are stripped to canonical
`?`-form, IS the same logic variable, not two different ones) and
leaves that are still genuinely unknown at this point (APPEND's `Z`,
never mentioned anywhere else in the clause). Those unresolved leaves
are `:HOLE`s, re-checked against the clause's variable bindings again
AFTER the body is compiled (`RESOLVE-TEMPLATE`) -- picking up anything
a body `LISP-EVAL`/`IS`/`UNIFY` step bound in the meantime -- and
whatever's STILL a hole after that must be produced by the clause's own
trailing moded call, matched BY NAME against that call's own outputs
(every remaining hole must appear among them; an output the call
produces but this clause doesn't need is fine, just unused). Anything
left unresolved even after that is a compile-time error naming the
actual offending output position -- not a function that silently
returns the wrong thing (added two new error-case tests to `mode-
tests.lisp` for exactly this: an output with literally no producer at
all, and one where a trailing call happens but its outputs don't cover
what's needed).

### The TCO trade-off -- read this before assuming every moded predicate is O(1) stack

This is the one genuinely new cost this feature introduces, and it's
real, not a bug: the ORIGINAL "fast path" -- every output is a single,
never-otherwise-bound hole whose name matches the trailing call's own
output names, in order -- is UNCHANGED and still compiles to a literal
Lisp tail call (COUNT-UP3, RELAY, LISTSUM, DOUBLED3 above all still get
genuine O(1)-stack TCO, confirmed unaffected: their generated code is
byte-for-byte identical to before this feature existed). But APPEND
needs to cons `X` onto whatever the recursive call produces for `Z` --
it needs that call's RESULT before it can finish building its own
output -- so `COMPILE-DET-CLAUSE` falls back to wrapping the call in
`MULTIPLE-VALUE-BIND` and reconstructing the real output afterward.
That's correct, but it's not a tail call: it costs one real Lisp stack
frame per recursive step, exactly like the equivalent hand-written
non-tail-recursive Lisp or Prolog definition of `append` would cost.
Measured directly (see `6sum.lisp`): lists of 2,000/10,000/50,000
elements append fine; a list of 100,000 is a genuine FATAL process
crash under `sbcl --script`'s default control stack -- "Control stack
exhausted", not a catchable Lisp condition, confirmed empirically
rather than assumed (a `HANDLER-CASE` around it does not help; the
crash is at the OS/runtime level). `6sum.lisp` stops its own escalating
test at 50,000 deliberately, for exactly this reason -- there is no
"catch it gracefully and report" demonstration worth having when the
failure mode is a hard process crash, not a condition. This is not a
regression to fix later so much as an honest fact about this specific
shape of recursion, the same one any Lisp or Prolog implementation
faces: build-the-result-on-the-way-back-up recursion is not
tail-recursive, full stop, and DOUBLED above is kept written in its
accumulator style specifically to show the alternative -- when a
problem's shape allows it, choosing the accumulator+final-reverse form
over the more "natural-looking" cons-after-recursing form is what
buys back the O(1)-stack guarantee.

### Testing

`6sum.lisp`: `listsum` (car/cdr input reading, tail-recursive,
cross-checked against an interpreted-engine helper), `doubled`
(cons-building via an accumulator, tail-recursive, likewise
cross-checked), `append` (Eduardo's own compound-pattern example
verbatim, cross-checked directly against the interpreted engine since
`append`'s stored clauses are ordinary cons-pattern Prolog -- no
`lisp-eval` involved in its structural part at all, so the `eval-
prolog-form` rough edge below doesn't apply to it), and the
escalating-list-size stack-depth demonstration described above.
`mode-tests.lisp` gained `firstof` (the old "badcons" error case,
repurposed as a positive regression check for simple `+`-side
destructuring) and two new error-case tests for output positions with
no valid producer. The full existing suite (`mode-tests.lisp`, `mode-
multivalue-tests.lisp`, `fortran-mode-tests.lisp`, `bench-mode.lisp`)
was re-run afterward and confirmed unaffected -- same results, same
generated code for every existing predicate (verified by the fast-path
condition being exactly as strict as the original single-level check
used to be).

## Roadmap: becoming a full-fledged Prolog (2026-09-14)

Eduardo: this project is going to keep going -- the destination isn't
"a fast toy that runs `count-up3` and `queens8`," it's a Prolog with
everything a Prolog has. He named four things explicitly as what's
missing right now: `findall/3`, `bagof/3`, `setof/3`, `call/N`. This
section is the concrete plan for getting there, written so that
whoever (whichever session) picks this up next doesn't have to
rediscover the plan from scratch -- see the ORIENTATION section at the
very top of this file, which points here.

None of what follows has been started. This is a design sketch, not a
report of work done -- treat every implementation claim below as "worth
checking against the actual current source before trusting it," since
the engine will keep changing between now and whenever this is picked
up.

### The real prerequisite underneath all four: a reusable, runtime meta-call

`findall/3`, `bagof/3`, and `setof/3` all need to run a goal that isn't
known until runtime (their second argument, `Goal`) and enumerate every
one of its solutions, not just the first. `call/N` needs to run a goal
built at runtime (a partially-applied term with N-1 more arguments
appended) exactly once, cut-transparently, as if it had been written
directly in the calling clause's body. Both needs come down to the same
missing piece: a way to hand an arbitrary, only-known-at-runtime term to
the engine's own goal-solving machinery and get results back, callable
FROM inside a running goal -- not just the top-level `?-`/`?-all` query
entry points.

Before writing any of `findall`/`bagof`/`setof`/`call`, the first real
task is figuring out (by reading the current `prolog-engine.lisp`, which
will have moved on from what's described elsewhere in this file by the
time you're reading this) whether that reusable entry point already
exists in some form, or needs to be factored out of `?-`/`?-all`. Things
to check specifically:
- How does the general (interpreted) resolution loop dispatch one goal
  at a time -- is there already a function like "solve this one goal
  term against the current bindings, calling a continuation/producing a
  generator of solutions, with backtracking into it available"? If so,
  that's very likely most of what `findall`/`call` need underneath;
  the work is exposing/wrapping it, not building it from scratch.
- How does v6's per-clause COMPILER handle a body goal whose predicate
  isn't statically known at compile time (which is exactly what
  `call/N` needs, and it's also relevant to any goal built from a
  variable rather than a literal functor)? If compiled clauses assume a
  fixed, known-at-compile-time functor for every body goal, compiled
  clauses will need an explicit "this one goal isn't statically known,
  fall back to the general interpreted solver for it" escape hatch --
  check whether that fallback already exists for any other reason
  (e.g. an unindexed variable-headed goal) before building a new one.
- How are variable bindings walked/copied when a query finishes (i.e.
  whatever machinery prints `?RESULT = ...`)? `findall`'s Template
  needs exactly this: given the current bindings, produce a fully
  dereferenced, self-contained Lisp term (copying any variable that's
  still unbound to a fresh one, or leaving a distinguishable
  unbound-marker) that survives after the trail is unwound. Reuse
  whatever already does this rather than writing a second copy.

### `findall(Template, Goal, List)`

Semantics: solve Goal, and for EVERY solution (backtracking through all
of it, exactly like `?-all` does at the top level), copy Template under
that solution's current bindings and collect it. Unlike `bagof`/`setof`,
`findall` never fails -- zero solutions just binds `List` to `()`. No
grouping, no existential-variable handling; this is the simplest of the
three and should be built and proven first, since `bagof`/`setof` are
naturally built ON TOP of the same "run Goal, backtrack through every
solution, collecting a copy of Template each time" core loop.

Implementation sketch, contingent on what the prerequisite section above
finds: drive Goal via the general solver, and on each success, walk
Template's current bindings into a fresh ground(ish) copy (see above),
push it onto an accumulator (built in solution order -- `findall/3`'s
list order is defined to be solution order, this isn't a place to take
a shortcut with e.g. an unordered collection), then force backtracking
into Goal's last choice point (undoing its trail, same as ordinary
backtracking already does) to look for the next solution, and repeat
until Goal is exhausted. Finally `unify*` `List` against the
accumulated Lisp list, once, unconditionally.

### `bagof(Template, Goal, List)` / `setof(Template, Goal, List)`

Both are `findall/3` plus:
1. Fail (don't just bind an empty list) when Goal has zero solutions.
2. Understand `^` (existential quantification): `Var^Goal` means "don't
   group solutions by Var's binding, even though Var appears free in
   Goal." Needs a small preprocessing pass over the Goal term to strip
   `^`/2 wrappers and collect the quantified variables before running
   Goal for real.
3. GROUP solutions by the bindings of Goal's free variables -- any
   variable that appears in Goal but not in Template and not
   `^`-quantified away. `bagof`/`setof` can backtrack into MULTIPLE
   different `List` bindings, one per distinct combination of free-
   variable bindings that made Goal true at least once. This is real
   algorithmic work: classify Goal's variables (Template vars vs
   existential vs free), collect `(free-var-bindings . template-copy)`
   pairs across every solution the way `findall` already does, then
   partition that flat collection by free-var-bindings (using
   whatever the engine's term-equality check already is -- structural
   equality on the fully-dereferenced free-variable bindings, not `eq`)
   and offer one partition's Template-list per `bagof` solution.
4. `setof/3` additionally sorts each such list (standard order of
   terms -- if no term-ordering comparator exists yet, that's a small
   prerequisite of its own) and removes adjacent duplicates after
   sorting.

Get `findall/3` solid and well-tested first -- it's the core loop
`bagof`/`setof` both need, and it's testable in complete isolation from
the grouping logic, which is the part actually worth taking slowly.

### `call(Goal)`, `call(Goal, A1)`, ..., `call(Goal, A1, ..., Ak)`

Construct a new goal term by appending the extra arguments (`A1` ...
`Ak`) onto Goal's own argument list (`Goal` is typically a predicate
symbol alone, or a partially-applied compound term -- `call/N` doesn't
care which, it just appends), then solve the resulting compound term
exactly as if it had appeared literally in the calling clause's body at
that position -- including honoring cut-transparency rules (a `!` inside
the called goal cuts choice points created *within that call*, not the
caller's own choice points -- standard-Prolog semantics, worth writing
a test that specifically exercises this, since it's an easy thing to
get subtly wrong).

Two separate places need this, and they may need separate work:
- The general interpreted engine: presumably already solves one goal at
  a time via a functor/arity lookup into `*database*` performed AT THE
  MOMENT the goal is solved, not baked in earlier -- if so, `call/N`
  here is mostly just "build the compound term, hand it to whatever
  that per-goal solve step already is." Confirm this by reading the
  loop rather than assuming it.
- v6's per-clause COMPILER: a compiled clause's body goals are almost
  certainly resolved against known predicate symbols at `compile`
  time (that's the whole point of the per-clause compiler -- see the v6
  section above). A goal built by `call/N` is fundamentally not known
  until runtime, so a compiled clause containing a `call/N` (or any
  goal headed by a variable) needs an explicit fallback to the general
  interpreted solve path for that one goal, mid-clause. This is very
  likely the single trickiest integration point in this whole roadmap --
  budget real design time for it rather than treating it as a
  formality once `findall`/`bagof`/`setof` are done.

### Also probably needed eventually (not explicitly requested yet --
### secondary to the four above, listed so they aren't forgotten)

`\+/1` (negation as failure -- needs the same "run Goal, see if it has
at least one solution, then undo everything" primitive `findall`
needs), `assert/1`/`retract/1` (RUNTIME database modification, distinct
from `<-`, which asserts at Lisp-macro-expansion/load time -- this
changes what "the database" even means while a query is mid-flight, a
real semantic question, not just an API addition), a standard-order-of-
terms comparator (needed by `setof/3` above, and generally useful),
and library predicates like `member/2`/`append/3`/`length/2`/
`between/3` (some of these might already be reasonable to write as
ordinary user-defined Prolog clauses via `<-` once the engine is
solid, rather than needing to be built-ins).

### Status update: the roadmap above is partly done

`findall/3`, `bagof/3`, `setof/3`, and `call/N` (the first four items
above) were implemented and deployed after this roadmap section was
written, along with a real fix to `eval-prolog-form` (it was mishandling
a dereferenced variable bound to a list). This paragraph exists so this
file doesn't actively mislead a future reader into re-doing work that's
already there -- see `prolog-engine.lisp` itself for the current state
of those predicates rather than trusting the roadmap prose above, which
was left as originally written for its reasoning, not its status.

## `pipeline.lisp`: a reusable external-pipeline library (2026-09-14)

### Why this exists

`sarcoma-setup.x` in `umap-sarcoma` was ported from a flat sequence of
`sb-ext:run-program` calls to a Prolog port (`SUBSTEP/5` facts giving
stage/position/description/script/args, grouped and ordered by
`SETOF`). That first port moved the *sequencing and grouping* into
Prolog but left the actual "launch a process, check its exit code,
report a failure, read an env var" mechanism as ~20 lines of
hand-written Lisp at the top of the script -- and Eduardo pointed out,
correctly, that this made the port a wash: "you added 22 lines in Lisp
as prefix, Prolog didn't represent a substantial gain... more Prolog,
less Lisp." That mechanism isn't sarcoma-specific at all, so it
belongs in claude-prolog itself, written once, not duplicated at the
top of every consuming script -- and the actual success/failure
DECISION (as opposed to the unavoidably-Lisp act of starting an OS
process) is exactly the kind of small dispatch Prolog clause selection
already does better than a Lisp `if`: one clause matching the literal
exit code `0` (with a cut), one catch-all clause matching any `?code`
that reports failure.

### What it provides

Load `pipeline.lisp` after `prolog-engine.lisp`. A consuming script
then needs only:

1. `(setf *pipeline-root* ...)` -- nothing in Lisp can introspect
   "which directory is the SCRIPT THAT LOADED ME in" from inside a
   library file (`*load-truename*` only reflects whichever file is
   being loaded at the moment it's read), so the consuming script must
   capture its own truename itself, once, at its own top level.
   `*pipeline-sbcl*` also exists as a `defparameter`, defaulting to
   `(getenv-or "SBCL" (namestring sb-ext:*runtime-pathname*))` --
   preserving the original script's own documented `SBCL`
   environment-variable override -- and can be `setf` again afterward
   for a non-environment-variable override.
2. `SUBSTEP/5` facts: `(substep StageNumber PositionInStage
   Description ScriptPath ArgList)` -- the pipeline's actual content,
   and the one part that's genuinely specific to each script, so it
   stays in the script, not in this library.
3. One call: `(?- (run-pipeline))`.

Everything else -- grouping by stage, ordering within a stage,
launching each external process, deciding success from failure, and
reporting a failure clearly -- lives in `pipeline.lisp`, and every
decision in it (as opposed to the mechanism of starting a process) is
a Prolog clause, not a Lisp `if`:

```
(<- (handle-stage-result ?description 0) !)
(<- (handle-stage-result ?description ?code)
    (lisp-eval t (fail-stage ?description ?code)))
```

`getenv-or`, `announce-stage`, `run-process-raw`, and `fail-stage` are
the small named Lisp callables underneath (`run-process-raw` is where
`*pipeline-root*` is required to be set, erroring loudly if not,
rather than silently falling back to the OS's own current directory).

### Effect on `sarcoma-setup.x`

With `pipeline.lisp` doing the generic work, `sarcoma-setup.x` itself
shrank to just its own `ENV-VALUE`/`SUBSTEP` facts plus loading the two
library files and calling `(?- (run-pipeline))` -- no
`run-external-stage`, no `getenv-or` definition, no exit-code `if`, all
of that now lives in claude-prolog and is shared by any future
consuming script instead of being re-typed at the top of each one.

### Verification

Tested in isolation first, against two stub scripts (`step-ok.lisp`,
always exits 0 and prints its args; `step-fail.lisp`, always exits 1)
with a synthetic 2-stage/3-substep pipeline:
- basic success path: correct stage/substep sequencing and argument
  passing, `(?- (run-pipeline))` returns `yes` and the script's own
  code after it still runs;
- failure path: a synthetic 3-stage pipeline where stage 2 fails --
  confirmed stage 3 never runs and the whole script aborts uncaught
  with a non-zero exit code, matching the pre-library behavior exactly;
- the `SBCL` environment-variable override: confirmed
  `*pipeline-sbcl*` actually picks up `SBCL=/usr/bin/sbcl` from the
  environment at load time (an earlier draft of this file computed
  `*pipeline-sbcl*` before `getenv-or` was even defined and silently
  ignored the environment variable entirely -- caught before deploying
  anywhere, fixed by moving `getenv-or`'s definition first).

Then re-verified end-to-end with the real `sarcoma-setup.x` (rewritten
to load and use `pipeline.lisp`) against the same stubbed-pipeline
smoke-test harness used for the original Prolog port: identical stage
sequencing and arguments; `SAR_EPOCHS`/`SAR_LR` overrides still reach
the Train Transformer stage; a forced failure in the stubbed
`validate-corpus.lisp` still aborts before the Train/HTML stages run,
exactly as before.

### If this needs to be revisited

The library assumes every stage is a `sbcl --script <path> <args...>`
subprocess and that "exit code 0" is the only definition of success --
true of every pipeline built on this so far, but a future consumer
needing a non-SBCL subprocess, a success check other than exit code
0, or output-capturing (`run-process-raw` currently wires
`:output t :error t`, i.e. straight through to the terminal, not
captured) would need either a parallel predicate or a small extension
here, not a fork.

### A note on why `/areas/claude-prolog.md` exists in Eduardo's persistent
### memory now, and what it's for

Eduardo asked directly whether a NOTES.md file can fix a Claude session
showing up with no memory of this project. Honest answer, also recorded
in the conversation this section was written in: partially, and only if
a future session actually opens this file -- nothing about this cloud
environment forces that to happen automatically for a project living in
a connected folder on someone else's machine (unlike, say, an in-repo
`CLAUDE.md` auto-loaded because it sits in a session's own working
directory). So a small `/areas/claude-prolog.md` entry now lives in
Eduardo's Claude persistent-memory store (the part of memory that DOES
get loaded automatically at the start of every session, regardless of
which machine or working directory that session happens to be in) --
its whole job is to say "this project exists, here's where it lives on
disk, and NOTES.md there has the full history and the current roadmap,
read it first." That's the actual fix for "you haven't the slightest
idea what we were doing": not this file alone, but this file PLUS a
memory entry that guarantees a future session at least knows to go look
for it. If that memory entry is ever missing, out of date, or wrong,
fix it the same turn you notice -- it's cheap to maintain and it's the
one thing standing between "picks this up in five minutes" and "starts
from zero."
