# General AWRS-SMC engine

This directory contains the domain-independent Adaptive Weighted Rejection
Sampling and Sequential Monte Carlo implementation. Stock-specific proposal
spaces, potentials, and corpus-curation rules live in `../stk-specific/`.

Run its general tests from the project root:

```sh
sbcl --script awrs-smc/tests.lisp
```

Do not introduce stock names, ticker conventions, or market features here. If
a change is genuinely general, apply the identical change in `umap-sarcoma`.

## Recent changes

- **RNG replaced.** `awrs-random-unit` now uses SplitMix64 (Steele, Lea &
  Flood 2014) instead of a 32-bit linear congruential generator. Same call
  signature everywhere, but every seed now produces different numbers than
  before -- any previously saved AWRS-SMC search result (e.g.
  `output/*-awrs-smc-result.sexp`) will not reproduce byte-for-byte from the
  same seed anymore; it needs to be regenerated.
- **`AWRS-SAMPLE` has no budget/`:ADDITIONAL-TRACES` parameter.** It always
  runs Definition 2 exactly as the paper states it: one accepted trace plus
  one continuation trace. An earlier version of this codebase added such a
  parameter by analogy with `:RESAMPLING-METHOD`'s sibling concept in WRS
  (Definition 1, which the paper does prove for a general budget); that
  analogy is wrong for AWRS and produces provably biased weights for L>1
  (a two-outcome counterexample gives E[ZHAT]=13/24 instead of 1/2). See
  `AWRS-SAMPLE`'s docstring for the full explanation. No correct general-L
  AWRS estimator is known, so the parameter was removed rather than merely
  restricted -- do not re-add it without an actual proof.
- **`RUN-AWRS-SMC` takes `:RESAMPLING-METHOD`** (`:MULTINOMIAL`, the default
  and the source paper's Algorithm 2, or `:SYSTEMATIC`, a lower-variance
  opt-in implemented in `SYSTEMATIC-RESAMPLE`).
- `AWRS-SMC-RESULT-SELECTED` is a stochastic draw from the final weighted
  particle population (the literal SMC output). Every caller in this project
  ignores it and instead re-ranks `PARTICLES` by its own quality metric to
  get a single deterministic "best" particle -- that pattern is correct and
  intentional, not a bug; `-SELECTED` is documented in `smc.lisp` for anyone
  who does want a posterior-proportional draw instead.
