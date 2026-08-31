(:format :umap-problem
 :version 1
 :title "Experiment 1: ten temporal anchors"
 :data (:file "temporal-10-windows.sexp"
        :records-key :records
        :id-field :id
        :embedding ((:field :vector))
        :validation
        (:required-fields (:id :vector :curve :sarcoma-type :therapy)
         :unique-fields (:id)))
 :preprocessing (:standardize true)
 :umap (:neighbors 100 :minimum-distance 0.72 :epochs 500 :seed 20260831
        :density-surface true :density-bandwidth 58 :density-thresholds 10
        :density-opacity 0.12 :density-color "data" :density-color-bands 7
        :point-radius 6)
 :views ((:field :sarcoma-type :label "Sarcoma type" :type "categorical")
         (:field :therapy :label "Therapy" :type "categorical")
         (:field :histology :label "Histology" :type "categorical")
         (:field :study :label "Study" :type "categorical")
         (:field :window-survival :label "Survival at window start" :type "continuous")
         (:field :local-drop :label "Local survival decline" :type "continuous"))
 :tooltip ((:field :study :label "Study")
           (:field :sarcoma-type :label "Sarcoma type")
           (:field :therapy :label "Therapy")
           (:field :endpoint :label "Endpoint")
           (:field :primary-event :label "Primary event")
           (:field :cohort-size :label "Cohort")
           (:field :window-start-months :label "Window start (months)")
           (:field :window-end-months :label "Window end (months)"))
 :tooltip-plot (:kind "kaplan-meier" :field :curve
                :x-label "Months" :y-label "Event-free proportion"))
