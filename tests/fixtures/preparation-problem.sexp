(:format :umap-problem
 :version 1
 :title "Preparation fixture"
 :preparation (:kind :evidence-windows
               :source "preparation-source.sexp"
               :schema fixture-windows/1
               :temporal-profile-count 2
               :window-widths (0.25)
               :survival-transform :identity
               :include-survival-progress false
               :use-typed-transforms false)
 :data (:file "../tmp/preparation-records.sexp"
        :records-key :records
        :id-field :id
        :embedding ((:field :vector))))
