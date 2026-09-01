(:format :umap-problem
 :version 1
 :title "Pilot UMAP of sarcoma evidence statistics"
 :preparation (:kind :evidence-windows
               :source "data/pilot-landmarks.sexp"
               :schema evidence-windows/1
               :temporal-profile-count 10
               :window-widths (0.125 0.25 0.50)
               :survival-transform :identity
               :include-survival-progress true
               :use-typed-transforms false)
 :data (:file "data/pilot-windows.sexp"
        :records-key :records
        :id-field :id
        :embedding ((:field :vector))
        :validation
        (:required-fields (:id :vector :curve :sarcoma-type :therapy)
         :unique-fields (:id)))
 :preprocessing (:standardize true)
 :umap (:neighbors 300 :minimum-distance 0.72 :epochs 500 :seed 20260831
        :density-surface true :density-bandwidth 58 :density-thresholds 10
        :density-opacity 0.18 :density-color "data" :density-color-bands 7
        :point-radius 6)
 :scoring (:label-field :sarcoma-type :beta 1.0
           :output "output/pilot-problem-score.sexp"
           :clustering (:algorithm :dbscan :minimum-points 5
                        :epsilon :automatic))
 :views ((:field :sarcoma-type :label "Sarcoma type" :type "categorical")
         (:field :window-scale :label "Window scale" :type "categorical")
         (:field :therapy :label "Therapy" :type "categorical")
         (:field :histology :label "Histology" :type "categorical")
         (:field :study :label "Study" :type "categorical")
         (:field :window-survival :label "Survival at window start" :type "continuous")
         (:field :local-drop :label "Local survival decline" :type "continuous"))
 :tooltip ((:field :study :label "Study")
           (:field :sarcoma-type :label "Sarcoma type")
           (:field :therapy :label "Therapy"
            :omit-prefix "Population survival")
           (:field :endpoint :label "Endpoint")
           (:field :primary-event :label "Primary event")
           (:field :window-scale :label "Window scale")
           (:field :cohort-size :label "Cohort")
           (:field :window-start-months :label "Window start (months)")
           (:field :window-end-months :label "Window end (months)"))
 :tooltip-plot (:kind "kaplan-meier" :field :curve
                :x-label "Months" :y-label "Event-free proportion"))
