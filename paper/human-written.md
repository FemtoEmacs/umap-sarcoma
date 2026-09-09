# AI skill for Multidimensional Evidence

## Author list

Amanda Santos; Alina Santos; Pedro Fernandes; Thales Oliveira Lima; Luciano Lima; Marcus Santos; Alex Santos; Antonio E. Costa

## Introduction

The authors of this paper wanted to analyze the quantitative magnetic resonance T2 mapping described by Souza et al. in their 2023 paper [1]. Basically, the authors replaced the traditional method of determining the maximum diameter of desmoid tumors with a specific tissue response. They used Generative AI to build a clinical evidence map for a network analysis framework into which they could insert the paper. In this work, we will describe what a clinical evidence map is (at least how we understand the term), the network analysis framework and where Generative AI can help or must be avoided.

Let us start by showing how we can use Codex GPT 6 Astra and Claude AI to check the above paragraph against our own documentation and the reference to provide details and catch mistakes.


**Astra fact checking.** Souza et al. did not replace maximum tumor diameter with a tissue-response measure. They conducted a preliminary, retrospective study of quantitative MRI T2 relaxation time as a possible imaging biomarker in 11 patients with desmoid fibromatosis; nine patients had longitudinal examinations. The investigators measured maximum diameter, tumor volume, conventional T2-weighted signal, and absolute T2 relaxation time, and compared responses based on size and signal. At best response, the mean change in T2 relaxation time was -17.9% (p=0.05), whereas the mean change in maximum diameter was -8.9% (p=0.12). T2 mapping also had high inter-reader reliability (intraclass correlation coefficient 0.84). These preliminary findings support T2 mapping as a promising quantitative measure of tissue response, not as an established replacement for RECIST 1.1 or maximum-diameter measurement. The evidence is limited by the retrospective design, the small convenience sample, heterogeneous prior treatment, variable MRI acquisition, the absence of a uniform true pretreatment baseline, and use of a two-dimensional region of interest on one representative slice rather than whole-tumor T2-map segmentation [1].


**Claude AI fact-check:** Souza et al. didn't "replace" the diameter method — they proposed T2 mapping as a complementary quantitative alternative alongside diameter, and explicitly frame it as feasibility/preliminary work, not a replacement. The "tissue response" phrase is accurate — it echoes the Desmoid Tumor Working Group's call to integrate tissue response into RECIST-style criteria.

**Claude AI style check:** "They" in your sentence is ambiguous — the nearest antecedent is "the quantitative magnetic resonance T2 mapping described by Souza et al.," so a reader could momentarily parse "They" as referring to the mapping technique itself rather than the authors. Since the paper's authors and your paper's authors ("the authors" in your first sentence) are different groups, I'd disambiguate explicitly, e.g., "Our paper's authors used Generative AI..." or "We used Generative AI...".


**Author evaluation of AI for manuscript editing and proofreading.** In general, authors could use GenAI for proofreading, as long as they are careful to verify that proposed rewrites don't change the meaning of the sentence. One must also be aware of extensive AI rewriting, which could cause AI detectors to classify the passage as AI-written.

As for manuscript editing, we notice that AI reports are long and full of irrelevant, often incorrect details. Therefore, authors have to carefully select what to include in the AI-driven modifications they make to the manuscript. Here is how we would rewrite our text after reading the AI style and fact-checking:

*The authors of the present paper wanted to review quantitative magnetic resonance T2 mapping described by Souza et al. in their 2023 publication [1]. In the cited paper, the authors proposed T2 mapping as a complementary quantitative measurement alongside diameter to assess desmoid tumor progression and therapeutic response.*

*We also used Generative AI to build a clinical evidence map for a network analysis framework into which we could insert Souza's paper. In this work, we will describe what a clinical evidence map is (at least the manner we understand the term), the network analysis framework and where Generative AI can help or must be avoided.*


## AI support for software development

In the introductory section, we concluded that authors can't do without proofreaders and manuscript editors. The next question we want to answer is more delicate. To what extent can researchers in fields like medicine, finance and investment count on AI support? Opinions vary. In one extreme, some researchers outside computer science claim that for simple statistical problems with a large training corpus, GenAI can write functional applications. In the other extreme, a dwindling group of people insists that AI can't do anything useful beyond code auto-complete; therefore, it won't improve the productivity of human coders. 

To test whether Codex can increase a coder's productivity, the author created a parametric UMAP to classify sarcoma studies [2]. Each study is represented in a multidimensional feature space that changes by area. For instance, a point in the sarcoma-study space can be defined by author, sarcoma type, therapy, end-point, primary event, window scale, cohort, etc. After finding the points, we need to reduce the dimensions, since humans have difficulty visualizing structures in a multidimensional space. We used UMAP for dimension reduction [3]. The ultimate goal of this work was to classify the sarcoma studies. Then, we needed to find clusters in the UMAP space. Reference [4] shows the final result. 

Codex GPT should be able to find citations in the documentation or on the Internet and add them to the Reference section.

The first thing Codex GPT, or any other GenAI for that matter, could help with is data mining the feature values needed for the UMAP. This is a really time-consuming task in two stages: (1) finding the data and (2) storing them on the computer in a convenient format, such as S-expressions [9], CSV (comma-separated values), or compressed files, such as h5ad. The authors of the present work worked with ionospheric physics, the stock market, sarcoma and medical specialties. In all experiments, Codex GPT struggled to find the main data sources. In this regard, human help is mandatory. However, once the data is in the computer, Codex GPT has no trouble finding a method for handling missing data and storing it in the requested file format (CSV or S-expression, in our case).

## Writing code

Writing code has many facets. For example, the programmer could follow instructions in English and test the resulting code. This is called informal specification. For small algorithms, Codex GPT can implement informal specifications very well. We won't insist on informal specifications because the reader can test them easily with simple scripts.

Another way to program is to recycle code from Internet repositories. Since GitHub is the most popular repository, people call this method of coding GitHub software engineering.

GitHub engineering is the first choice for many programmers. When a Python programmer calls BLAS/LAPACK or NumPy, they are using a variant of black-box GitHub engineering. This variant is called black-box because the programmer usually doesn't care about checking the source code of BLAS/LAPACK or whatever library they use. However, black-box GitHub engineering is not the one we want to evaluate. What we are interested in is assembling a program from snippets of repository code and using Differential Testing to check the result.

To simplify the discussion, we can admit that GenAI is really only good at building n-grams by choosing a high-probability next token. Then, if we want it to generate a program in Common Lisp, we can offer it a pool of C implementations to draw tokens from. Why provide a pool of implementations instead of letting Codex datamine them? On the Internet, there are thousands of ramen-programmers outputting spaghetti code (they are called ramen-programmers for a reason), but only a bunch of people like Edi Weiz. The reader only has to gain by enforcing Weiz-quality code.

To narrow things down, assume Edi Weiz uploaded a C program to a GitHub repository, and you want it in Common Lisp to incorporate into your framework. I link the C code to Common Lisp through the CFFI interface and keep the original implementation as an oracle. Then, Codex replaces each C function with an equivalent Lisp function and tests the whole against the oracle. If the result differs, Codex mutates the translation and tries again. Once a function is translated, Codex moves to the next until all C is converted. Then the human coder checks the converted function to see whether the transpiling was done well.

Why is human-checking necessary? Codex and other GenAI often replace a difficult goal with an easier one. It may replace a difficult algorithm with a less efficient one. The differential testing will not detect the replacement. For instance, Codex may replace the quicksort algorithm with bubble sort. It may also use naive data structures, such as representing vectors as lists and arrays as lists of lists. If this happens, the human programmer must enforce the use of arrays.

Considering that a human coder must check Codex's work, it is necessary to implement a simpler pilot first. In [4], the Transformer Architecture has fewer than 500 lines, which a human programmer can check in half a day. If the final user needs a supercharged application, they may implement it later.

## Other applications
When the pilot is working, the developers can ask Codex to generalize it, i.e., apply the same programs to a different area. For instance, the very same Lisp program that was implemented for classify sarcoma studies, can be used for stocks [5] or medical specialties[6].

## Documentation

We will start this section with a quotation from Taylor D. [7]: Two years of AI tooling discourse, and most of it has been fighting over that 14%. Documentation is consistently the #1 thing developers want AI to help with. Not autocomplete. Not refactoring. Documentation. Google's most utilized internal AI tool helps engineers navigate their own engineering system docs. Then, let us check whether Codex can navigate the project documentation described in this paper and explain how it works.

Codex GPT, describe how the parametric UMAP implemented in /stock-umap works. Describe its main modules: ~/stock-umap/build-umap.lisp, ~/stock-umap/TOUR.md, ~/stock-umap/README.md and ~/stock-umap/data in the root folder, ~/stock-umap/awrs-smc and ~/stock-umap/smc-trainer. Add references and citations where needed (for instance, cite Alexander Lew when talking about awrs-smc). Make the discussion short: five to ten lines for each subject. Don't erase this prompt.

This section was written entirely by Codex GPT, a GenAI, to show its ability to document a project it assisted with. A full discussion of the usefulness of GenAI in projects like this one is left to the Conclusion section. However, I advise the reader not to spend their precious time trying to understand what Codex GPT wrote below. It may have many strengths, but writing isn't one of them.

Codex GPT 6 Astra, write the next subsection. At the beginning of the subsection, add a warning that the subsection was entirely written by a GenAI.

### A clinical evidence map for network analysis


## Old stuff
This section was written entirely by Codex GPT, a GenAI, to show its ability to document a project it assisted with. A full discussion of the usefulness of GenAI in projects like this one is left to the Conclusion section. However, I advise the reader not to spend their precious time trying to understand what Codex GPT wrote below. It may have many strengths, but writing isn't one of them.

The project first constructs a fixed, nonparametric UMAP atlas from measured
stock properties, following the neighborhood-preserving method of McInnes et
al. [3]. It then trains a small Transformer to learn a parametric function from
the 36-dimensional stock vector to the atlas's two coordinates, an approach
related to Parametric UMAP [2]. An unseen stock can therefore be inserted
without recalculating UMAP or moving the original points. The atlas describes
historical similarity; it does not forecast returns or recommend investments.

### `build-umap.lisp`

`build-umap.lisp` is the general, manifest-driven page builder. It reads the
problem S-expression, resolves and validates the declared CSV data, applies
the requested transformations, and places the records and configuration in an
HTML page. The page either displays preserved coordinates or computes UMAP in
the browser with pinned JavaScript modules. Domain names and stock features
remain in the manifest and data rather than being hardcoded in the builder.
The build itself requires SBCL but no Quicklisp, Python, Node.js, or Conda [5].

### `TOUR.md`

`TOUR.md` is the executable guide and the shortest route through the complete
experiment. Its ordered commands reproduce the first stock-month map, robust
company profiles, the S&P 500 atlas, design search, negative controls, corpus
curation, Transformer training, and insertion of unseen stocks. With
`stock-tour.el`, Emacs opens the guide above a dedicated Eshell; `C-c e` runs
the shell block at point. Expected row counts, scores, and browser checks make
the tour both documentation and a manual reproducibility test [5].

### `README.md` and `data/`

`README.md` is the reference manual: it records requirements, commands,
schemas, feature definitions, outputs, tests, and scientific limitations.
`data/` separates preserved sources from derived tables. The reproducible S&P
500 run starts with a saved constituent snapshot and cached Nasdaq daily CSVs,
then derives 29,926 stock-month records for 498 securities and 36 numerical
properties. Derived CSV files should be rebuilt, not edited by hand. The notes
also disclose survivorship, membership look-ahead, and corporate-action risks,
so the data are suitable for method testing rather than trading claims [5].

### `awrs-smc/`

`awrs-smc/` contains the domain-independent particle engine; stock proposal
spaces, constraints, and scoring potentials remain under `stk-specific/`.
Candidate analytical designs are proposed, rejected when invalid, weighted by
their evidence, and resampled when effective sample size becomes too small.
The audit output retains particles, weights, rejections, ESS, resampling, and
the selected design. This project adapts the AWRS-SMC idea rather than claiming
an identical language-model sampler. The cited AWRS work includes Alexander K.
Lew and combines adaptive rejection with SMC importance correction [8].

### `smc-trainer/`

`smc-trainer/` implements the learned map from 36 properties to two fixed
atlas coordinates. Its small Transformer represents features as tokens and
uses native Common Lisp arrays and explicit numerical loops, without
BLAS/LAPACK. Portable S-expressions store the corpus and trained weights. In
the preserved experiment, 280 confident cluster-core stocks train the model
and 15 difficult boundary stocks remain withheld for validation. Prediction
inserts a new point into the fixed atlas; it does not rerun UMAP or alter the
positions of the training stocks [5].

## Conclusion

This work implemented a non-trivial Generative AI application with the assistance of Codex GPT 6 to assess the productivity gains this new way of programming can bring.  The subjective evaluation of the outcomes is summarized below.

1. Documentation. At the time of this writing, Generative AI cannot write clear text or gauge and outline the complex structure of a software project. The authors of the present paper built a TOUR.md to guide the GenAI in building an application outline, but it didn't work very well.
2. Use Differential Testing to extract usefull components from an open-source application. For instance, Codex GPT 6 Astra was able to isolate and create oracles for the Transformer architecture in C [10,11]. Then, it transpiled the code to Common Lisp and tested it against the oracles. When the authors of the present paper checked the code, they discovered that arrays were implemented as nested lists. They requested an array implementation, and Codex fixed the code in less than ten minutes. Differential testing and code isolation represent a huge productivity gain.
3. Create code from an algorithm description in the literature. Codex GPT 6 implemented Alexander K. Lew's awrs-smc algorithm without human intervention. The algorithm is given in pseudo-Python in [8]. This also assures productivity gains.

In conclusion, for an experienced programmer, GenAI assistance brings undeniable productivity gains. However, beginners must be aware of the following GenAI vulnerabilities and weak points:

1. Intent misalignment occurs when an AI system's goals, behaviors, or inner reward functions do not match human values, safety measures, or intended outcomes. Codex using lists instead of arrays is an example of intent misalignment. Another example is implementing bubble sort when the project manager asked for quicksort. GenAI often fails to align with human values, such as efficiency, speed and safety.
2. Using naive algorithms, such as lists to store a corpus, instead of shards.
3. GenAI doesn't know how to implement general tools. If you ask for a parametric UMAP and give Codex a sarcoma database, the program won't work for stocks. After finishing a system like parametric UMAP, make sure that it works for many applications. With human guidance and intervention, it is possible to obtain general code from Codex.
4. Neighborhood effect. Codex often reuses code from another application on the same machine. If this occurs, the project manager won't be able to distribute the code.
5. The goal of GenAI is to pass the test suite, not to solve your problem—one of the authors of the present paper asked for awrs-smc-optimized clusters. Codex generated the clusters, but not the HTML for visualization. It wasn't possible to include HTML visualization in the test suite; therefore, Codex didn't implement it.


## References

[1] Souza FF, D'Amato G, Jonczak EE, Costa P, Trent JC, Rosenberg AE,
Yechieli R, Temple HT, Pattany P, and Subhawong TK. MRI T2 mapping assessment
of T2 relaxation time in desmoid tumors as a quantitative imaging biomarker of
tumor response: preliminary results. *Frontiers in Oncology*. 2023;13:1286807.
https://doi.org/10.3389/fonc.2023.1286807

[2] Sainburg T, McInnes L, and Gentner TQ. Parametric UMAP embeddings for
representation and semisupervised learning. *Neural Computation*.
2021;33(11):2881–2907. https://doi.org/10.1162/neco_a_01434

[3] McInnes L, Healy J, Saul N, and Großberger L. UMAP: Uniform Manifold
Approximation and Projection. *Journal of Open Source Software*.
2018;3(29):861. https://doi.org/10.21105/joss.00861

[4] Costa Pereira AE. *UMAP Sarcoma: dependency-free Common Lisp evidence
mapping and scoring* [software and interactive website].
https://github.com/FemtoEmacs/umap-sarcoma;
https://femtoemacs.github.io/umap-sarcoma/. Accessed September 7, 2026.

[5] https://femtoemacs.github.io/stock-umap/

Costa Pereira AE. *Stock UMAP* [software and interactive website]. Source code:
https://github.com/FemtoEmacs/stock-umap. Accessed September 7, 2026.

[6] https://femtoemacs.github.io/specialty-umap/

Costa Pereira AE. *Medical Specialty UMAP* [software and interactive website].
Source code: https://github.com/FemtoEmacs/specialty-umap. Accessed September 7,
2026.

[7] Taylor D. Developers spend 86% of their day on non-coding tasks,
prioritizing empathy can drive lasting change [LinkedIn post].
https://www.linkedin.com/posts/onlydole_developers-spend-roughly-14-of-their-day-activity-7417273197785567234-tWm0.
Accessed September 7, 2026.

[8] Lipkin B, LeBrun B, Vigly JH, et al. Fast controlled generation from
language models with adaptive weighted rejection sampling. 2025.
arXiv:2504.05410. https://doi.org/10.48550/arXiv.2504.05410

[9] Rivest RL and Eastlake D. *S-Expressions*. Internet-Draft
draft-rivest-sexp-02, Network Working Group. July 8, 2023. Work in progress.
https://www.ietf.org/archive/id/draft-rivest-sexp-02.html

[10] Saeed H. *C-Transformer: Implementation of the core Transformer architecture
in pure C* [software]. https://github.com/hasanisaeed/C-Transformer. Accessed
September 7, 2026.

[11] Bartwal K. *Encoder Transformer From Scratch in C* [software].
https://github.com/KartikeyBartwal/Encoder-Transformer-From-Scratch-in-C/.
Accessed September 7, 2026.


