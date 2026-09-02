;;;; Build a clinician-facing before/after demonstration of parametric insertion.

(defparameter *demo-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defparameter *demo-root* (merge-pathnames "../../" *demo-directory*))
(defparameter *build-umap-run-main* nil)
(load (merge-pathnames "build-umap.lisp" *demo-root*))
(defparameter *parametric-predict-run-main* nil)
(load (merge-pathnames "smc-trainer/predict.lisp" *demo-root*))

(defun demo-mean-input (records label)
  (let* ((selected (remove-if-not (lambda (record)
                                    (equal label (getf record :label)))
                                  records))
         (dimension (length (getf (first selected) :input))))
    (loop for column below dimension collect
      (/ (loop for record in selected sum (nth column (getf record :input)))
         (length selected)))))

(defun demo-raw-values (standardized preprocessing)
  (loop for value in standardized
        for mean in (getf preprocessing :means)
        for scale in (getf preprocessing :scales)
        collect (+ mean (* value scale))))

(defun demo-existing-points (records)
  (loop for record in records collect
    (list :id (getf record :id) :group (getf record :group)
          :label (getf record :label) :cluster (getf record :cluster)
          :x (first (getf record :target)) :y (second (getf record :target))
          :new nil)))

(defun demo-new-points (corpus artifact)
  (let* ((records (getf corpus :records))
         (labels (sort (remove-duplicates (mapcar (lambda (r) (getf r :label)) records)
                                          :test #'equal)
                       #'string<))
         (model (form-parametric-model (getf artifact :model)))
         (preprocessing (getf artifact :preprocessing)))
    (loop for label in labels for index from 0
          for base = (demo-mean-input records label)
          for input = (loop for value in base for component from 0
                            collect (+ value (* 0.06d0
                                                (sin (+ 1 component index)))))
          for coordinates = (parametric-predict model input)
          collect
          (list :id (format nil "NEW-~2,'0D" (1+ index))
                :name (format nil "Illustrative new ~A profile" label)
                :group "Hypothetical demonstration"
                :label label :cluster nil
                :x (first coordinates) :y (second coordinates)
                :new t :shape index
                :raw-features (demo-raw-values input preprocessing)))))

(defun demo-json-text (value)
  (with-output-to-string (stream) (write-json value stream)))

(defun build-insertion-demo (corpus-name weights-name output-name)
  (let* ((corpus (predict-read-form corpus-name))
         (artifact (predict-read-form weights-name))
         (existing (demo-existing-points (getf corpus :records)))
         (new (demo-new-points corpus artifact))
         (template (file-text (merge-pathnames "insertion-demo-template.html"
                                               *demo-directory*)))
         (page (replace-marker
                (replace-marker template "__ATLAS_POINTS__" (demo-json-text existing))
                "__NEW_POINTS__" (demo-json-text new))))
    (ensure-directories-exist output-name)
    (with-open-file (stream output-name :direction :output :if-exists :supersede
                                        :if-does-not-exist :create)
      (write-string page stream))
    (format t "Wrote ~D atlas points and ~D projected examples to ~A.~%"
            (length existing) (length new) output-name)))

(let ((arguments (cdr sb-ext:*posix-argv*)))
  (unless (= (length arguments) 3)
    (error "Usage: sbcl --script smc-trainer/demo/build-demo.lisp CORPUS WEIGHTS OUTPUT.html"))
  (apply #'build-insertion-demo arguments))
