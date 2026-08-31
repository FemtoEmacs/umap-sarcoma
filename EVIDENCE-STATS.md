# Evidence statistics for the UMAP atlas

The unit embedded by UMAP should be an auditable evidence object: a study arm,
comparison, endpoint, time window, or patient trajectory whose fields retain a
source locator. Plot pixels are not data. Missing, unclear, not reported, not
applicable, and not calculated values must remain distinct.

## Recommended evidence families

1. **Time to event**
   - Kaplan-Meier curves for progression-free survival, overall survival,
     event-free survival, duration of response, and time to progression
   - cumulative-incidence curves for competing risks
   - restricted mean survival time and landmark survival probabilities
   - median time to event, hazard ratio, confidence interval, censoring,
     numbers at risk, follow-up, and proportional-hazards diagnostics
2. **Tumor response at a fixed assessment**
   - waterfall plots and RECIST response categories
   - objective response rate, disease-control rate, best percentage change,
     denominator, assessment time, and confirmation status
3. **Treatment course and durability**
   - swimmer plots
   - treatment start and stop, response onset, progression, ongoing response,
     censoring, dose interruption, surgery, crossover, and subsequent therapy
4. **Longitudinal tumor kinetics**
   - spider plots and repeated target-lesion measurements
   - change from baseline, slope, nadir, rebound, assessment spacing, dropout,
     and within-patient variability
5. **Comparative effects**
   - forest plots
   - hazard ratios, risk ratios, odds ratios, mean differences, confidence
     intervals, estimand, adjustment status, and subgroup interaction tests
6. **Treatment exposure**
   - dose intensity, dose reductions, interruptions, discontinuation reasons,
     cumulative dose, treatment duration, adherence, and crossover
7. **Safety and tolerability**
   - adverse-event incidence by grade and attribution
   - serious adverse events, treatment-related discontinuation, toxicity onset,
     duration, and resolution
8. **Patient-reported and functional outcomes**
   - pain, symptom burden, quality of life, physical function, clinically
     important change, response durability, and missingness
9. **Imaging and nonstandard high-precision evidence**
   - MRI T2 mapping, volumetry, PET uptake, radiomics, or another defined method
   - measurement target, acquisition timing, repeatability, change from
     baseline, and explicit boundaries on conventional estimands not calculated
10. **Study context and evidence quality**
    - design, phase, setting, sample size, eligibility, line of therapy,
      comparator, follow-up, analysis population, missingness, risk-of-bias
      domains, endpoint role, and reporting completeness
11. **Meta-analytic structure**
    - study-level effect and standard error, between-study variance,
      heterogeneity, prediction intervals, influence diagnostics, and small-study
      effect or funnel-plot information when statistically appropriate

## Features likely to produce useful UMAP neighborhoods

Use several complementary blocks rather than one large bag of heterogeneous
numbers:

- **shape block:** resampled curve or trajectory values on declared normalized
  and absolute-time grids, slopes, area summaries, landmarks, and curvature;
- **magnitude block:** effect estimates and uncertainty, transformed only with
  a declared domain-appropriate rule;
- **support block:** sample size, events, follow-up, censoring, numbers-at-risk
  completeness, and missingness;
- **design block:** randomized versus observational, comparator type, endpoint
  role, analysis population, and adjustment;
- **display block:** Kaplan-Meier, cumulative incidence, waterfall, swimmer,
  spider, forest, safety, patient-reported outcome, or NSHP;
- **therapy block:** sorafenib, nirogacestat, pazopanib, anthracycline-containing
  regimens, local therapy, active surveillance, and future interventions;

Curve provenance is audit metadata, not an embedding block. Author-supplied,
digitized, and reconstructed curves enter the same numerical representation
after the same endpoint-specific normalization. Their origin, extraction
method, source locator, reviewer status, and extraction confidence remain in
the database and hover audit panel, but are excluded from PCA and UMAP inputs.
An optional source-stratified sensitivity check may test this assumption later;
it must not determine the primary map.

Continuous nonnegative heavy-tailed variables such as sample size, event count,
follow-up, and treatment duration may use `log10(1+x)`. Signed effects,
percent changes, probabilities, categorical fields, and censoring indicators
must use suitable encodings rather than that transform. Fit scaling and any PCA
only on the training or reference set, retain missingness indicators, balance
feature blocks so dense curves do not overwhelm design and quality, and validate
neighborhood stability across seeds, feature ablations, and leave-study-out
runs.

## Visual design

For pancreas-like regions, render density contours behind small points and let
the viewer recolor the same stable embedding by therapy, evidence family,
endpoint, study, design, effect direction, evidence adequacy, or review status.
UMAP proximity is exploratory similarity, not treatment ranking or proof of
clinical equivalence.

No clinical or publication conclusion should be generated until a physician or
qualified reviewer verifies every material source extraction and its locator.
