;;;; Validate single-file or sharded Parametric UMAP corpora.

(defparameter *parametric-validation-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(unless (fboundp 'parametric-open-corpus-source)
  (load (merge-pathnames "shards.lisp" *parametric-validation-directory*)))
(defvar *validate-parametric-corpus-run-main* t)

(defun corpus-read-form (path) (parametric-read-one-form path))

(defun corpus-finite-real-p (value)
  (and (realp value) (= value value)
       (< (abs (coerce value 'double-float)) most-positive-double-float)))

(defun validate-parametric-corpus (path)
  (let* ((source (parametric-open-corpus-source path))
         (metadata (parametric-source-metadata source))
         (preprocessing (getf metadata :preprocessing))
         (means (getf preprocessing :means)) (scales (getf preprocessing :scales))
         (dimension (length means)) (count 0) (training 0)
         (ids (make-hash-table :test #'equal))
         (group-splits (make-hash-table :test #'equal)))
    (unless (and (plusp dimension) (= dimension (length scales)))
      (error "Corpus needs matching preprocessing vectors."))
    (unless (every (lambda (scale) (and (corpus-finite-real-p scale) (plusp scale))) scales)
      (error "Every preprocessing scale must be finite and positive."))
    (parametric-map-records
     source
     (lambda (record)
       (let ((id (getf record :id)) (group (getf record :group))
             (split (getf record :split)) (input (getf record :input))
             (target (getf record :target)))
         (unless (and id group (member split '(:train :validation)))
           (error "Invalid record identity or split: ~S." record))
         (when (gethash id ids) (error "Duplicate record ID ~S." id))
         (setf (gethash id ids) t)
         (let ((known (gethash group group-splits)))
           (when (and known (not (eq known split)))
             (error "Group ~S crosses train and validation splits." group))
           (setf (gethash group group-splits) split))
         (unless (and (= (length input) dimension) (= (length target) 2)
                      (every #'corpus-finite-real-p input)
                      (every #'corpus-finite-real-p target))
           (error "Invalid numeric input or target for ~S." id))
         (when (eq split :train) (incf training))
         (incf count))))
    (unless (plusp training) (error "Corpus has no training records."))
    (when (and (eq (getf source :kind) :shards)
               (/= count (getf metadata :record-count)))
      (error "Manifest record count does not match its shards."))
    (format t "Validated ~D records, ~D features, ~D groups.~%"
            count dimension (hash-table-count group-splits))
    source))

(when *validate-parametric-corpus-run-main*
  (let ((arguments (cdr sb-ext:*posix-argv*)))
    (unless (= (length arguments) 1)
      (error "Usage: sbcl --script smc-trainer/validate-corpus.lisp CORPUS-OR-MANIFEST"))
    (validate-parametric-corpus (first arguments))))
