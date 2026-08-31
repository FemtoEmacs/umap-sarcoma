(:schema evidence-landmarks/1
 :endpoint progression-free-survival
 :time-unit month
 :curves
 ((:id desmoid-sorafenib
   :study "Gounder et al. 2018"
   :doi "10.1056/NEJMoa1805052"
   :disease-family "Desmoid-type fibromatosis"
   :sarcoma-type "Desmoid tumor"
   :histology "Desmoid tumor"
   :therapy "Sorafenib"
   :primary-event "Progression"
   :event-code 0
   :cohort-size 49
   :follow-up-months 27.2
   :objective-response-rate 0.33
   :time-to-response-months 9.6
   :pfs-hazard-ratio 0.13
   :model :weibull-landmarks
   :landmarks ((12 0.89) (24 0.81))
   :maximum-months 48
   :acquisition "author-informed")
  (:id desmoid-placebo
   :study "Gounder et al. 2018"
   :doi "10.1056/NEJMoa1805052"
   :disease-family "Desmoid-type fibromatosis"
   :sarcoma-type "Desmoid tumor"
   :histology "Desmoid tumor"
   :therapy "Placebo"
   :primary-event "Progression"
   :event-code 0
   :cohort-size 38
   :follow-up-months 27.2
   :objective-response-rate 0.20
   :time-to-response-months 13.3
   :pfs-hazard-ratio 1.0
   :model :weibull-landmarks
   :landmarks ((12 0.46) (24 0.36))
   :maximum-months 48
   :acquisition "author-informed")
  (:id sts-pazopanib
   :study "van der Graaf et al. 2012 (PALETTE)"
   :doi "10.1016/S0140-6736(12)60651-5"
   :disease-family "Soft-tissue sarcoma"
   :sarcoma-type "Soft-tissue sarcoma"
   :histology "Non-adipocytic soft-tissue sarcoma"
   :therapy "Pazopanib"
   :primary-event "Death"
   :event-code 1
   :cohort-size 246
   :median-os-months 12.5
   :pfs-hazard-ratio 0.31
   :os-hazard-ratio 0.86
   :model :exponential-median
   :median-pfs-months 4.6
   :median-months 12.5
   :endpoint "Overall survival"
   :maximum-months 36
   :acquisition "author-informed")
  (:id sts-placebo
   :study "van der Graaf et al. 2012 (PALETTE)"
   :doi "10.1016/S0140-6736(12)60651-5"
   :disease-family "Soft-tissue sarcoma"
   :sarcoma-type "Soft-tissue sarcoma"
   :histology "Non-adipocytic soft-tissue sarcoma"
   :therapy "Placebo"
   :primary-event "Death"
   :event-code 1
   :cohort-size 123
   :median-os-months 10.7
   :pfs-hazard-ratio 1.0
   :os-hazard-ratio 1.0
   :model :exponential-median
   :median-pfs-months 1.6
   :median-months 10.7
   :endpoint "Overall survival"
   :maximum-months 36
   :acquisition "author-informed")
  (:id osteosarcoma-map
   :study "Smeland et al. 2019 (EURAMOS-1)"
   :doi "10.1016/j.ejca.2018.11.027"
   :disease-family "Bone sarcoma"
   :sarcoma-type "Bone sarcoma"
   :histology "High-grade osteosarcoma"
   :therapy "MAP-based treatment strategy"
   :primary-event "Death"
   :event-code 1
   :endpoint "Overall survival"
   :cohort-size 2260
   :follow-up-months 54
   :os-landmarks ((36 0.79) (60 0.71))
   :model :weibull-landmarks
   :efs-landmarks ((36 0.59) (60 0.54))
   :landmarks ((36 0.79) (60 0.71))
   :maximum-months 96
   :acquisition "author-informed")
  (:id chondrosarcoma-ivosidenib
   :study "Tap et al. 2020"
   :doi "10.1200/JCO.19.02492"
   :disease-family "Bone sarcoma"
   :sarcoma-type "Bone sarcoma"
   :histology "Advanced IDH1-mutant chondrosarcoma"
   :therapy "Ivosidenib"
   :primary-event "Overall survival not reported"
   :event-code 0
   :cohort-size 21
   :disease-control-rate 0.52
   :model :weibull-landmarks
   :landmarks ((5.6 0.50) (6 0.395))
   :maximum-months 18
   :acquisition "author-informed")
  (:id gist-imatinib-400
   :study "Casali et al. 2017"
   :doi "10.1200/JCO.2016.71.0228"
   :disease-family "GIST"
   :sarcoma-type "GIST"
   :histology "Advanced CD117-positive GIST"
   :therapy "Imatinib 400 mg/day"
   :primary-event "Death"
   :event-code 1
   :cohort-size 473
   :follow-up-months 130.8
   :median-os-months 46.8
   :os-landmarks ((120 0.194))
   :pfs-hazard-ratio 1.0
   :model :weibull-landmarks
   :median-pfs-months 20.4
   :pfs-landmarks ((20.4 0.50) (120 0.095))
   :landmarks ((46.8 0.50) (120 0.194))
   :endpoint "Overall survival"
   :maximum-months 120
   :acquisition "author-informed")
  (:id gist-imatinib-800
   :study "Casali et al. 2017"
   :doi "10.1200/JCO.2016.71.0228"
   :disease-family "GIST"
   :sarcoma-type "GIST"
   :histology "Advanced CD117-positive GIST"
   :therapy "Imatinib 800 mg/day"
   :primary-event "Death"
   :event-code 1
   :cohort-size 473
   :follow-up-months 130.8
   :median-os-months 46.8
   :os-landmarks ((120 0.215))
   :pfs-hazard-ratio 0.91
   :model :weibull-landmarks
   :median-pfs-months 24
   :pfs-landmarks ((24 0.50) (120 0.092))
   :landmarks ((46.8 0.50) (120 0.215))
   :endpoint "Overall survival"
   :maximum-months 120
   :acquisition "author-informed")
  (:id sts-local-1999-2004 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "Soft-tissue sarcoma" :histology "STS, localized/regional"
   :therapy "Population survival, 1999-2004" :primary-event "Death" :event-code 1
   :survival-progress-delta -0.001
   :median-os-months 105 :model :weibull-landmarks :landmarks ((60 0.606) (105 0.50))
   :endpoint "Overall survival" :maximum-months 180 :acquisition "author-informed")
  (:id sts-local-2005-2011 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "Soft-tissue sarcoma" :histology "STS, localized/regional"
   :therapy "Population survival, 2005-2011" :primary-event "Death" :event-code 1
   :survival-progress-delta -0.001
   :median-os-months 97 :model :weibull-landmarks :landmarks ((60 0.599) (97 0.50))
   :endpoint "Overall survival" :maximum-months 180 :acquisition "author-informed")
  (:id sts-local-2012-2019 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "Soft-tissue sarcoma" :histology "STS, localized/regional"
   :therapy "Population survival, 2012-2019" :primary-event "Death" :event-code 1
   :survival-progress-delta -0.001
   :model :exponential-landmark :landmarks ((60 0.605))
   :endpoint "Overall survival" :maximum-months 120 :acquisition "author-informed")
  (:id sts-distant-1999-2004 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "Soft-tissue sarcoma" :histology "STS, distant"
   :therapy "Population survival, 1999-2004" :primary-event "Death" :event-code 1
   :survival-progress-delta 0.001
   :median-os-months 8 :model :weibull-landmarks :landmarks ((8 0.50) (60 0.101))
   :endpoint "Overall survival" :maximum-months 96 :acquisition "author-informed")
  (:id sts-distant-2005-2011 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "Soft-tissue sarcoma" :histology "STS, distant"
   :therapy "Population survival, 2005-2011" :primary-event "Death" :event-code 1
   :survival-progress-delta 0.001
   :median-os-months 8 :model :weibull-landmarks :landmarks ((8 0.50) (60 0.092))
   :endpoint "Overall survival" :maximum-months 96 :acquisition "author-informed")
  (:id sts-distant-2012-2019 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "Soft-tissue sarcoma" :histology "STS, distant"
   :therapy "Population survival, 2012-2019" :primary-event "Death" :event-code 1
   :survival-progress-delta 0.001
   :median-os-months 9 :model :weibull-landmarks :landmarks ((9 0.50) (60 0.102))
   :endpoint "Overall survival" :maximum-months 96 :acquisition "author-informed")
  (:id gist-local-1999-2004 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "GIST" :histology "GIST, localized/regional"
   :therapy "Population survival, 1999-2004" :primary-event "Death" :event-code 1
   :survival-progress-delta 0.079
   :median-os-months 133 :model :weibull-landmarks :landmarks ((60 0.724) (133 0.50))
   :endpoint "Overall survival" :maximum-months 240 :acquisition "author-informed")
  (:id gist-local-2005-2011 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "GIST" :histology "GIST, localized/regional"
   :therapy "Population survival, 2005-2011" :primary-event "Death" :event-code 1
   :survival-progress-delta 0.079
   :median-os-months 157 :model :weibull-landmarks :landmarks ((60 0.773) (157 0.50))
   :endpoint "Overall survival" :maximum-months 240 :acquisition "author-informed")
  (:id gist-local-2012-2019 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "GIST" :histology "GIST, localized/regional"
   :therapy "Population survival, 2012-2019" :primary-event "Death" :event-code 1
   :survival-progress-delta 0.079
   :model :exponential-landmark :landmarks ((60 0.803))
   :endpoint "Overall survival" :maximum-months 180 :acquisition "author-informed")
  (:id gist-distant-1999-2004 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "GIST" :histology "GIST, distant"
   :therapy "Population survival, 1999-2004" :primary-event "Death" :event-code 1
   :survival-progress-delta 0.115
   :median-os-months 33 :model :weibull-landmarks :landmarks ((33 0.50) (60 0.343))
   :endpoint "Overall survival" :maximum-months 120 :acquisition "author-informed")
  (:id gist-distant-2005-2011 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "GIST" :histology "GIST, distant"
   :therapy "Population survival, 2005-2011" :primary-event "Death" :event-code 1
   :survival-progress-delta 0.115
   :median-os-months 53 :model :weibull-landmarks :landmarks ((53 0.50) (60 0.454))
   :endpoint "Overall survival" :maximum-months 150 :acquisition "author-informed")
  (:id gist-distant-2012-2019 :study "Hardy et al. 2025 (SEER 9)" :doi "10.1002/cncr.35906"
   :sarcoma-type "GIST" :histology "GIST, distant"
   :therapy "Population survival, 2012-2019" :primary-event "Death" :event-code 1
   :survival-progress-delta 0.115
   :median-os-months 53 :model :weibull-landmarks :landmarks ((53 0.50) (60 0.458))
   :endpoint "Overall survival" :maximum-months 150 :acquisition "author-informed")))
