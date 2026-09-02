;;;; Train the feature-token Transformer on single-file or sharded corpora.

(defparameter *parametric-train-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(load (merge-pathnames "transformer.lisp" *parametric-train-directory*))
(unless (fboundp 'parametric-open-corpus-source)
  (load (merge-pathnames "shards.lisp" *parametric-train-directory*)))

(defvar *parametric-train-run-main* t)

(defun trainer-split-metrics (model source split)
  (let ((squared-error 0.0d0) (absolute-error 0.0d0) (coordinates 0)
        (records 0))
    (parametric-map-records
     source
     (lambda (record)
       (incf records)
       (loop for prediction in (parametric-predict model (getf record :input))
             for target in (getf record :target) do
               (let ((difference (- prediction target)))
                 (incf squared-error (* difference difference))
                 (incf absolute-error (abs difference))
                 (incf coordinates))))
     :split split)
    (let ((mse (/ squared-error coordinates)))
      (list :records records :mse mse :rmse (sqrt mse)
            :mae (/ absolute-error coordinates)))))

(defun trainer-map-record-range (source split start end function)
  (let ((index 0))
    (parametric-map-records
     source
     (lambda (record)
       (when (and (<= start index) (< index end)) (funcall function record))
       (incf index))
     :split split)))

(defun trainer-map-rotated-records (source split epoch count function)
  "Stream the same deterministic rotation formerly applied to the full list."
  (let ((offset (mod (* epoch 17) count)))
    (trainer-map-record-range source split offset count function)
    (trainer-map-record-range source split 0 offset function)))

(defun train-parametric-source (source &key (epochs 100) (learning-rate 0.002d0))
  (let* ((training-count (parametric-count-records source :split :train))
         (validation-count (parametric-count-records source :split :validation))
         (first (parametric-first-record source :split :train)))
    (unless first (error "Corpus has no training records."))
    (let* ((feature-count (length (getf first :input)))
           (model (initialize-parametric-model feature-count))
           (optimizer (make-adam-state model)) (step 0))
      (format t "Training ~D records; validating on ~D records.~%"
              training-count validation-count)
      (loop for epoch from 1 to epochs do
        (trainer-map-rotated-records
         source :train epoch training-count
         (lambda (record)
           (let* ((prediction (transformer-forward model (getf record :input)))
                  (loss (parametric-coordinate-loss prediction (getf record :target))))
             (ad-backpropagate loss)
             (incf step)
             (adam-update model optimizer step :learning-rate learning-rate))))
        (when (or (= epoch 1) (= epoch epochs) (zerop (mod epoch 10)))
          (let ((train-metrics (trainer-split-metrics model source :train))
                (validation-metrics (trainer-split-metrics model source :validation)))
            (format t "Epoch ~3D train RMSE ~,6F validation RMSE ~,6F~%"
                    epoch (getf train-metrics :rmse)
                    (getf validation-metrics :rmse)))))
      (values model
              (list :epochs epochs :learning-rate learning-rate
                    :optimizer :adam :objective :coordinate-mse
                    :train (trainer-split-metrics model source :train)
                    :validation (trainer-split-metrics model source :validation))))))

(defun trainer-artifact-form (model source report)
  (let ((metadata (parametric-source-metadata source)))
    (list :format :trained-parametric-umap :version 1
          :model (parametric-model-form model)
          :feature-schema (getf metadata :feature-schema)
          :preprocessing (getf metadata :preprocessing)
          :split-policy (getf metadata :split-policy)
          :training-report report)))

(defun save-trainer-artifact (model source report path)
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output :if-exists :supersede
                               :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-readably* t))
      (write (trainer-artifact-form model source report) :stream stream)
      (terpri stream))))

(defun run-parametric-training (corpus-path output-path &key (epochs 100)
                                                           (learning-rate 0.002d0))
  (let ((source (parametric-open-corpus-source corpus-path)))
    (multiple-value-bind (model report)
        (train-parametric-source source :epochs epochs :learning-rate learning-rate)
      (save-trainer-artifact model source report output-path)
      (format t "Saved trained model to ~A.~%" output-path)
      report)))

(when *parametric-train-run-main*
  (let ((arguments (cdr sb-ext:*posix-argv*)))
    (unless (<= 2 (length arguments) 4)
      (error "Usage: sbcl --script smc-trainer/train.lisp CORPUS-OR-MANIFEST OUTPUT [EPOCHS [LEARNING-RATE]]"))
    (run-parametric-training
     (first arguments) (second arguments)
     :epochs (if (third arguments) (parse-integer (third arguments)) 100)
     :learning-rate (if (fourth arguments)
                        (coerce (read-from-string (fourth arguments)) 'double-float)
                        0.002d0))))
