# Sarcoma evidence feature catalogue

This is the candidate field list for extracting variables commonly reported in
sarcoma papers. A field enters the UMAP only when it has a defensible numerical
encoding and adequate coverage. Text labels remain available for coloring,
filtering, tooltips, and audit.

## Diagnosis and pathology

- `sarcoma-type`: desmoid tumor, soft-tissue sarcoma, bone sarcoma, or GIST.
- `histology`: the specific pathological diagnosis.
- `histologic-grade` and grading system.
- `differentiation`, necrosis, mitotic rate, and proliferation index (Ki-67).
- Primary anatomic site, depth, compartment, and laterality.
- Tumor size, multifocality, rupture, and margin status.

`sarcoma-type` replaces the redundant `disease-family` field. Histology stays
separate because osteosarcoma and chondrosarcoma, for example, are meaningfully
different within bone sarcoma.

## Molecular features

- Gene and exact alteration: substitution, insertion/deletion, amplification,
  deletion, fusion, rearrangement, or loss of expression.
- Protein change, exon/codon, fusion partner, and transcript when reported.
- Somatic versus germline status and pathogenicity classification.
- Variant allele frequency, copy number, clonality, and assay detection limit.
- Assay method, panel, specimen type, collection time, and tested/not-tested
  status.
- Driver class and pathway; actionable/targeted status at the time of study.
- Tumor mutational burden, microsatellite status, mutational signature, and
  relevant methylation or expression class when reported.

Frequently cited examples include:

- Desmoid tumor: `CTNNB1` T41A, S45F, S45P; germline or somatic `APC`.
- GIST: `KIT` exon 9/11/13/17; `PDGFRA` exon 12/14/18 including D842V;
  SDH deficiency (`SDHA/B/C/D` or SDHB immunohistochemistry), `NF1`, and `BRAF`.
- Chondrosarcoma: `IDH1` and `IDH2`, including the tested allele and inhibitor
  eligibility.
- Osteosarcoma: `TP53` and `RB1` disruption, copy-number burden, and genomic
  complexity. These should not be treated as uniform single-driver categories.
- Selected soft-tissue sarcomas: `SS18::SSX`, `EWSR1` fusions, `FUS::DDIT3`,
  `MDM2/CDK4` amplification, `SMARCB1` loss, `NTRK` fusion, and other
  histology-defining alterations.

Use the alteration itself in the embedding only after harmonization. Never use
“not reported” as wild type. Retain an assay/tested flag for audit, but exclude
reporting-pattern flags from distance calculations.

## Disease extent and patient context

- Localized, locally advanced, recurrent, or metastatic setting.
- Stage system and stage; metastatic sites and number of involved organs.
- Resectability, measurable disease, tumor burden, and baseline symptoms.
- Age, sex, performance status, comorbidity, and relevant hereditary syndrome.
- Prior operations, radiation, systemic treatments, and number of prior lines.

## Treatment

- Intervention and comparator, drug class, dose, schedule, and combination.
- Treatment line, neoadjuvant/adjuvant/metastatic intent, crossover, and rescue.
- Exposure duration, relative dose intensity, interruptions, reductions, and
  discontinuation reason.
- Surgery type and margin; radiation technique and dose; local ablation method.
- Biomarker-treatment match, such as imatinib with a susceptible GIST genotype.

## Outcomes and evidence statistics

- Clinically primary event: death, progression, recurrence/local failure, or a
  prespecified composite. Preserve the paper's definition.
- Overall, progression-free, event-free, disease-free, recurrence-free, local-
  control, and metastasis-free survival as applicable.
- Fixed-time survival, median time, hazard ratio, confidence interval, event
  count, follow-up, censoring, and numbers at risk.
- Objective response, complete/partial response, stable/progressive disease,
  disease-control rate, duration of response, and time to response.
- Waterfall change, swimmer duration, longitudinal/spider measurements, and
  quantitative imaging biomarkers.
- Patient-reported symptoms, pain, function, quality of life, and time to
  deterioration.
- Adverse events by grade, serious events, treatment-related death, and
  discontinuation for toxicity.

## Study and audit fields

- DOI, registry identifier, study design, phase, centers, country, enrollment
  dates, eligibility criteria, cohort and analysis-set sizes.
- Endpoint definition, assessment schedule, response criteria, and statistical
  method.
- Reported, digitized, reconstructed, or author-informed acquisition; source
  figure/table/page; reviewer and verification status.
- Risk-of-bias domains and conflicts/funding, retained for audit and sensitivity
  analysis rather than used as biological coordinates.

## Initial embedding policy

Use numerical biology and outcome measurements, including the clinically
primary event, mutation/pathway measurements with sufficient coverage, stage,
tumor burden, treatment exposure, survival/response, toxicity, and patient-
reported outcomes. Do not embed DOI, authors, study name, therapy name,
histology label, sarcoma label, data-acquisition label, or missing-reporting
patterns. Those fields are for interpretation, stratification, and auditing.

Molecular-field examples are supported by sarcoma cohorts studying CTNNB1 in
desmoid tumor (PMID 23960186), molecular subtypes of wild-type GIST (PMID
27011036), KIT/PDGFRA variant allele fraction (PMID 37463014), and prospective
clinical sequencing of soft-tissue and bone sarcomas (PMCID PMC9200818).
