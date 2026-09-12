# Sarcoma migration — 2026-09-11

The isolated repository now includes sarcoma-setup.x, an executable SBCL script that regenerates evidence, the full 600-observation map, AWRS search, study-grouped shards, a two-head/two-layer Transformer and the interactive contour/slider page. All user build stages use Common Lisp; no Node/npm dependency is introduced.

Outputs: output/sarcoma-full.html and output/cl-sarcoma-awrs-preferences.html. The pilot search retains its configured 90-observation limit. index.html now matches the generated Transformer page, with sarcoma-full.html alongside it for the full-map link.

The new page embeds complete source records joined by unique IDs, preserving all original popup declarations, extra view fields, DOI and full curve arrays. It reuses the existing Kaplan–Meier step rendering with labels and axes. Long popups scroll and remain visible when the pointer enters them. Synthetic profiles are explicitly identified and have no observed curve. Contours describe original clusters and exclude synthetic markers and noise.

Slider conversion applies the chosen feature transformation and artifact normalization directly. No empirical raw-value interpolation is used. Corpus/model schema and preprocessing must match.

Validation: 90 complete records/curves preserved, 540 feature conversions checked; JavaScript/Lisp prediction agreement across 90 records within 3.34e-15. Browser script syntax checked; visual browser inspection remains to be performed. Existing numerical suites passed 24 tests during initial import.

Full 100-epoch training completed: training coordinate RMSE 1.050894; validation RMSE 4.108131 (70/20 records, study-grouped). This gap limits confidence in hypothetical profile placement; it does not affect preservation of observed evidence or its curves. No clinical validation is implied.

Run ./sarcoma-setup.x, or sbcl --script sarcoma-setup.x. SAR_EPOCHS defaults to 100 and SAR_LR to 0.002d0. Run sbcl --script tests/sarcoma-page-tests.lisp after rebuilding.

Publication update: user rebuilt for 300 epochs. Saved training RMSE 0.5320441811 and validation RMSE 2.3999722563. Publishing includes the implementation, setup script and matching generated artifacts.
