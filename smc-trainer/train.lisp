;;;; Train the feature-token Transformer on an annotated AWRS-SMC corpus.

(defparameter *parametric-train-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(load (merge-pathnames "model.lisp" *parametric-train-directory*))

(defvar *parametric-train-run-main* t)

(defun trainer-read-form (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil)) (read stream))))

(defun trainer-records-for-split (corpus split)
  (remove-if-not (lambda (record) (eq split (getf record :split)))
                 (getf corpus :records)))

(defun trainer-record-loss-value (model record)
  (ad-value
   (parametric-coordinate-loss
    (parametric-forward model (getf record :input))
    (getf record :target))))

(defun trainer-split-metrics (model records)
  (let ((squared-error 0.0d0) (absolute-error 0.0d0) (coordinates 0))
    (dolist (record records)
      (loop for prediction in (parametric-predict model (getf record :input))
            for target in (getf record :target) do
              (let ((difference (- prediction target)))
                (incf squared-error (* difference difference))
                (incf absolute-error (abs difference))
                (incf coordinates))))
    (let ((mse (/ squared-error coordinates)))
      (list :records (length records) :mse mse :rmse (sqrt mse)
            :mae (/ absolute-error coordinates)))))

(defun trainer-rotated-records (records epoch)
  (let* ((count (length records)) (offset (mod (* epoch 17) count)))
    (append (subseq records offset) (subseq records 0 offset))))

(defun train-parametric-corpus (corpus &key (epochs 100) (learning-rate 0.002d0))
  (let* ((training (trainer-records-for-split corpus :train))
         (validation (trainer-records-for-split corpus :validation))
         (feature-count (length (getf (first training) :input)))
         (model (initialize-parametric-model feature-count))
         (optimizer (make-adam-state model)) (step 0))
    (format t "Training ~D records; validating on ~D records.~%"
            (length training) (length validation))
    (loop for epoch from 1 to epochs do
      (dolist (record (trainer-rotated-records training epoch))
        (let* ((prediction (parametric-forward model (getf record :input)))
               (loss (parametric-coordinate-loss prediction (getf record :target))))
          (ad-backpropagate loss)
          (incf step)
          (adam-update model optimizer step :learning-rate learning-rate)))
      (when (or (= epoch 1) (= epoch epochs) (zerop (mod epoch 10)))
        (let ((train-metrics (trainer-split-metrics model training))
              (validation-metrics (trainer-split-metrics model validation)))
          (format t "Epoch ~3D train RMSE ~,6F validation RMSE ~,6F~%"
                  epoch (getf train-metrics :rmse)
                  (getf validation-metrics :rmse)))))
    (values model
            (list :epochs epochs :learning-rate learning-rate
                  :optimizer :adam :objective :coordinate-mse
                  :train (trainer-split-metrics model training)
                  :validation (trainer-split-metrics model validation)))))

(defun trainer-artifact-form (model corpus report)
  (list :format :trained-parametric-umap :version 1
        :model (parametric-model-form model)
        :feature-schema (getf corpus :feature-schema)
        :preprocessing (getf corpus :preprocessing)
        :split-policy (getf corpus :split-policy)
        :training-report report))

(defun save-trainer-artifact (model corpus report path)
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output :if-exists :supersede
                               :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-readably* t))
      (write (trainer-artifact-form model corpus report) :stream stream)
      (terpri stream))))

(defun run-parametric-training (corpus-path output-path &key (epochs 100)
                                                           (learning-rate 0.002d0))
  (let ((corpus (trainer-read-form corpus-path)))
    (multiple-value-bind (model report)
        (train-parametric-corpus corpus :epochs epochs :learning-rate learning-rate)
      (save-trainer-artifact model corpus report output-path)
      (format t "Saved trained model to ~A.~%" output-path)
      report)))

(when *parametric-train-run-main*
  (let ((arguments (cdr sb-ext:*posix-argv*)))
    (unless (<= 2 (length arguments) 4)
      (error "Usage: sbcl --script smc-trainer/train.lisp CORPUS OUTPUT [EPOCHS [LEARNING-RATE]]"))
    (run-parametric-training
     (first arguments) (second arguments)
     :epochs (if (third arguments) (parse-integer (third arguments)) 100)
     :learning-rate (if (fourth arguments)
                        (coerce (read-from-string (fourth arguments)) 'double-float)
                        0.002d0))))
