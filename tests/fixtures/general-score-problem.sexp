(:format :umap-problem
 :version 1
 :title "General scoring fixture"
 :data (:file "general-score-data.sexp"
        :records-key :records
        :id-field :id
        :embedding ((:field :vector))
        :validation (:required-fields (:id :vector :diagnosis)
                     :unique-fields (:id)))
 :preprocessing (:standardize true)
 :umap (:neighbors 2 :minimum-distance 0.1 :epochs 20 :seed 19)
 :scoring (:label-field :diagnosis :beta 1.0
           :output "../tmp/general-score-result.sexp"
           :clustering (:algorithm :dbscan :minimum-points 2
                        :epsilon :automatic)))
