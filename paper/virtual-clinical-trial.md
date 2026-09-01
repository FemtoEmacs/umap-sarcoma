# A Local Virtual Clinical Trial

Many cancer treatments are tried in American hospitals. Only a small share of those experiences become published studies. Early trials take time, trained staff, statistical support, and physicians who can turn clinical work into a paper. Rare cancers such as sarcoma face an added problem: each hospital may see too few similar patients.

A local UMAP program could give physicians another way to study these cases. A doctor could obtain public SEER data, choose a group of patients, and compare records by age, tumor site, histology, stage, treatment, and survival. The program would calculate several UMAPs and score each one. The doctor would inspect the scores, choose the settings, and keep a complete record of every decision.

Cancer researchers have already reported useful results with this approach. Giraldo and colleagues studied tumor samples from 93 patients with metastatic melanoma. Their spatial UMAP identified tumor immune neighborhoods and clusters associated with five-year survival. The variables found by the unsupervised UMAP agreed with variables found by supervised methods. The authors described spatial UMAP as a tool for biomarker development.

In a study of 4,427 patients with myelodysplastic syndrome, D'Amico and colleagues combined UMAP with HDBSCAN. They reported finer patient groups than a conventional method. The average silhouette coefficient was 0.16 with UMAP and HDBSCAN and 0.01 with the comparison method. A random forest classified the resulting groups with a balanced accuracy of 92.7% ± 1.3%.

These studies show that UMAP can find patient neighborhoods, support clinical subgroup discovery, and identify patterns associated with prognosis. A physician-run program could apply the same form of analysis to public registry data. The physician would control the cohort, variables, parameters, score, and final comparison. The complete Common Lisp program would make the work repeatable at another hospital.

## References

1. McInnes L, Healy J, Saul N, Großberger L. UMAP: Uniform Manifold Approximation and Projection. *Journal of Open Source Software*. 2018;3(29):861. [doi:10.21105/joss.00861](https://doi.org/10.21105/joss.00861)

2. Giraldo NA, Berry S, Becht E, et al. Spatial UMAP and Image Cytometry for Topographic Immuno-oncology Biomarker Discovery. *Cancer Immunology Research*. 2021;9(11):1262–1269. [doi:10.1158/2326-6066.CIR-21-0015](https://doi.org/10.1158/2326-6066.CIR-21-0015); [PMID: 34433588](https://pubmed.ncbi.nlm.nih.gov/34433588/)

3. D'Amico S, Dall'Olio L, Rollo C, et al. MOSAIC: An Artificial Intelligence-Based Framework for Multimodal Analysis, Classification, and Personalized Prognostic Assessment in Rare Cancers. *JCO Clinical Cancer Informatics*. 2024;8:e2400008. [doi:10.1200/CCI.24.00008](https://doi.org/10.1200/CCI.24.00008); [PMID: 38875514](https://pubmed.ncbi.nlm.nih.gov/38875514/)

4. National Cancer Institute. SEER Variable and Recode Definitions. [SEER documentation](https://seer.cancer.gov/analysis/)
