;;;; Build the molecular-dimensions experiment. SBCL; no Quicklisp.

(defparameter *molecdim-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(load (merge-pathnames "src/evidence-windows.lisp" *molecdim-root*))

(defun molecdim-read (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil)) (read stream))))

(defun molecdim-context (curve-id)
  "Study-level molecular annotations. Binary features are deliberately
one-hot or indicator variables; missing molecular measurements remain zero."
  (cond
    ((member curve-id '(desmoid-sorafenib desmoid-placebo))
     (list :molecular-profile "WNT/beta-catenin pathway context"
           :alteration "CTNNB1/APC context"
           :molecular-source "Disease-context proxy"
           :vector '(1d0 0d0 0d0 0d0 0d0 0d0 0d0 0d0)))
    ((eq curve-id 'chondrosarcoma-ivosidenib)
     (list :molecular-profile "IDH1-mutant"
           :alteration "IDH1 mutation"
           :molecular-source "Study eligibility criterion"
           :vector '(0d0 0d0 0d0 1d0 0d0 1d0 1d0 1d0)))
    ((member curve-id '(gist-imatinib-400 gist-imatinib-800))
     (list :molecular-profile "KIT-pathway phenotype"
           :alteration "+CD-117+"
           :molecular-source "Study eligibility criterion"
           :vector '(0d0 1d0 0d0 0d0 0d0 1d0 1d0 1d0)))
    ((member curve-id '(gist-local-1999-2004 gist-local-2005-2011
                        gist-local-2012-2019 gist-distant-1999-2004
                        gist-distant-2005-2011 gist-distant-2012-2019))
     (list :molecular-profile "KIT/PDGFRA pathway context"
           :alteration "Mutation not reported in population stratum"
           :molecular-source "Disease-context proxy"
           :vector '(0d0 1d0 1d0 0d0 0d0 0d0 0d0 0d0)))
    ((eq curve-id 'osteosarcoma-map)
     (list :molecular-profile "Complex-genome context"
           :alteration "No single driver encoded"
           :molecular-source "Disease-context proxy"
           :vector '(0d0 0d0 0d0 0d0 1d0 0d0 0d0 0d0)))
    (t
     (list :molecular-profile "Heterogeneous or unreported"
           :alteration "No molecular selection encoded"
           :molecular-source "Not reported for this study stratum"
           :vector '(0d0 0d0 0d0 0d0 0d0 0d0 0d0 0d0)))))

(defun molecdim-annotate-record (record)
  (let* ((curve-id (intern (string-upcase (getf record :curve-id))))
         (context (molecdim-context curve-id)))
    ;; Source IDs are ordinary symbols, while the generated curve ID is text.
    (unless (getf context :molecular-profile)
      (error "Missing molecular annotation for ~A." curve-id))
    (setf (getf record :molecular-profile) (getf context :molecular-profile)
          (getf record :alteration) (getf context :alteration)
          (getf record :molecular-source) (getf context :molecular-source)
          (getf record :vector)
          (append (getf record :vector) (getf context :vector)))
    record))

(let* ((source (molecdim-read
                (merge-pathnames "data/pilot-landmarks.sexp" *molecdim-root*)))
       (records (mapcar #'molecdim-annotate-record
                        (evidence-all-multiscale-records (getf source :curves))))
       (output (merge-pathnames "data/molecdim-windows.sexp" *molecdim-root*)))
  (with-open-file (stream output :direction :output :if-exists :supersede
                                :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-circle* nil))
      (prin1 (list :schema 'molecular-evidence-windows/1 :records records) stream)
      (terpri stream)))
  (format t "Wrote ~A with ~D molecular evidence windows (~D dimensions).~%"
          output (length records) (length (getf (first records) :vector))))
