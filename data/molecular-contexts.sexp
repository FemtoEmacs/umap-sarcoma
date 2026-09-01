(:format molecular-contexts/1
 :contexts
 ((:curve-ids (desmoid-sorafenib desmoid-placebo)
   :molecular-profile "WNT/beta-catenin pathway context"
   :alteration "CTNNB1/APC context"
   :molecular-source "Disease-context proxy"
   :vector (1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0))
  (:curve-ids (chondrosarcoma-ivosidenib)
   :molecular-profile "IDH1-mutant"
   :alteration "IDH1 mutation"
   :molecular-source "Study eligibility criterion"
   :vector (0.0 0.0 0.0 1.0 0.0 1.0 1.0 1.0))
  (:curve-ids (gist-imatinib-400 gist-imatinib-800)
   :molecular-profile "KIT-pathway phenotype"
   :alteration "+CD-117+"
   :molecular-source "Study eligibility criterion"
   :vector (0.0 1.0 0.0 0.0 0.0 1.0 1.0 1.0))
  (:curve-ids (gist-local-1999-2004 gist-local-2005-2011
               gist-local-2012-2019 gist-distant-1999-2004
               gist-distant-2005-2011 gist-distant-2012-2019)
   :molecular-profile "KIT/PDGFRA pathway context"
   :alteration "Mutation not reported in population stratum"
   :molecular-source "Disease-context proxy"
   :vector (0.0 1.0 1.0 0.0 0.0 0.0 0.0 0.0))
  (:curve-ids (osteosarcoma-map)
   :molecular-profile "Complex-genome context"
   :alteration "No single driver encoded"
   :molecular-source "Disease-context proxy"
   :vector (0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0))
  (:curve-ids :otherwise
   :molecular-profile "Heterogeneous or unreported"
   :alteration "No molecular selection encoded"
   :molecular-source "Not reported for this study stratum"
   :vector (0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0))))
