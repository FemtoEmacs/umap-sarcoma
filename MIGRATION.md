# Sarcoma migration — 2026-09-11

The isolated repository now includes sarcoma-setup.x, an executable SBCL script that regenerates evidence, the full 600-observation map, AWRS search, study-grouped shards, a two-head/two-layer Transformer and the interactive contour/slider page. All user build stages use Common Lisp; no Node/npm dependency is introduced.

Outputs: output/sarcoma-full.html and output/cl-sarcoma-awrs-preferences.html. The pilot search retains its configured 90-observation limit. index.html now matches the generated Transformer page, with sarcoma-full.html alongside it for the full-map link.

The new page embeds complete source records joined by unique IDs, preserving all original popup declarations, extra view fields, DOI and full curve arrays. It reuses the existing Kaplan–Meier step rendering with labels and axes. Long popups scroll and remain visible when the pointer enters them. Synthetic profiles are explicitly identified and have no observed curve. Contours describe original clusters and exclude synthetic markers and noise.

Slider conversion applies the chosen feature transformation and artifact normalization directly. No empirical raw-value interpolation is used. Corpus/model schema and preprocessing must match.

Validation: 90 complete records/curves preserved, 540 feature conversions checked; JavaScript/Lisp prediction agreement across 90 records within 3.34e-15. Browser script syntax checked; visual browser inspection remains to be performed. Existing numerical suites passed 24 tests during initial import.

Full 100-epoch training completed: training coordinate RMSE 1.050894; validation RMSE 4.108131 (70/20 records, study-grouped). This gap limits confidence in hypothetical profile placement; it does not affect preservation of observed evidence or its curves. No clinical validation is implied.

Run ./sarcoma-setup.x, or sbcl --script sarcoma-setup.x. SAR_EPOCHS defaults to 100 and SAR_LR to 0.002d0. Run sbcl --script tests/sarcoma-page-tests.lisp after rebuilding.

Publication update: user rebuilt for 300 epochs. Saved training RMSE 0.5320441811 and validation RMSE 2.3999722563. Publishing includes the implementation, setup script and matching generated artifacts.

## claude-prolog replaced by qprolog — 2026-09-20

`sarcoma-setup.x` now runs on qprolog (`qprolog/`, a compiled, WAM-style Prolog engine in Common Lisp; see
`qprolog/README.md`) instead of claude-prolog. The `claude-prolog/` directory is removed (its history stays in
git), and with it the Edinburgh-notation reader (`edinburgh-reader.lisp`) and the separate
`sarcoma-setup-edinburgh.x` / `sarcoma-setup.pl` pair, which existed only to demonstrate that reader. Anyone
who wants Edinburgh syntax can translate ordinary `.pl` files with `qprolog/tr.x` (see `TOUR.md`).

* Same pipeline: identical stage order, identical `SAR_EPOCHS` / `SAR_LR` / `SBCL` overrides, identical
  stage scripts. Rebuilding with `SAR_EPOCHS=1` reproduces `output/cl-sarcoma-awrs-preferences.html` and
  `output/sarcoma-full.html` byte for byte compared with the claude-prolog version.
* The process-launching mechanism that used to be Lisp (`run-process-raw`, `getenv-or`, `fail-stage` in
  `claude-prolog/pipeline.lisp`) is now Prolog on top of new qprolog predicates that run shell commands and
  programs: `shell/1,2`, `shell_output/3`, `process_run/3,4`, `getenv/2`, `getenv_or/3`, `halt/1`
  (`qprolog/src/system.lisp`, documented in `qprolog/README.md`, section 7). The orchestration library is
  `qprolog/lib/pipeline.lisp`.
* Predicate names use underscores (`env_value`, `run_pipeline`), which ordinary Prolog allows.
* A failing stage prints `Stage <description> failed with exit code N.` and exits with status 1 (before: a Lisp
  backtrace).
