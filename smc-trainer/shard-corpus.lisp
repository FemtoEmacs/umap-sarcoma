;;;; Create group-preserving, independently readable S-expression shards.

(defparameter *shard-builder-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(unless (fboundp 'parametric-open-corpus-source)
  (load (merge-pathnames "shards.lisp" *shard-builder-directory*)))
(defvar *shard-corpus-run-main* t)

(defun shard-output-directory (path)
  (let ((text (namestring path)))
    (pathname (if (and (plusp (length text))
                       (char= (char text (1- (length text))) #\/))
                  text (concatenate 'string text "/")))))

(defun shard-group-records (records)
  "Collect every occurrence of a group, preserving first-group and within-group order."
  (let ((group-order nil) (groups (make-hash-table :test #'equal))
        (splits (make-hash-table :test #'equal)))
    (dolist (record records)
      (let* ((group (getf record :group)) (split (getf record :split))
             (known-split (gethash group splits)))
        (unless (gethash group groups) (push group group-order))
        (when (and known-split (not (eq known-split split)))
          (error "Study group ~S crosses corpus splits." group))
        (setf (gethash group splits) split)
        (push record (gethash group groups))))
    (mapcar (lambda (group) (nreverse (gethash group groups)))
            (nreverse group-order))))

(defun shard-pack-runs (runs limit)
  (let ((shards nil) (current nil) (count 0))
    (dolist (run runs)
      (when (and current (> (+ count (length run)) limit))
        (push (nreverse current) shards)
        (setf current nil count 0))
      (dolist (record run) (push record current))
      (incf count (length run)))
    (when current (push (nreverse current) shards))
    (nreverse shards)))

(defun shard-write-records (records path)
  (with-open-file (stream path :direction :output :if-exists :supersede
                               :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-readably* t))
      (dolist (record records) (write record :stream stream) (terpri stream)))))

(defun shard-corpus (input output-directory &key (record-limit 25))
  (unless (plusp record-limit) (error "Shard record limit must be positive."))
  (let* ((corpus (parametric-read-one-form input))
         (records (getf corpus :records))
         (directory (shard-output-directory output-directory))
         (packed (shard-pack-runs (shard-group-records records) record-limit))
         (descriptors nil))
    (unless (eq (getf corpus :format) :parametric-umap-corpus)
      (error "Input must be a single-file Parametric UMAP corpus."))
    (ensure-directories-exist (merge-pathnames "manifest.sexp" directory))
    (loop for shard in packed for index from 1
          for name = (format nil "shard-~6,'0D.sexp" index) do
            (shard-write-records shard (merge-pathnames name directory))
            (push (list :file name :records (length shard)
                        :groups (remove-duplicates
                                 (mapcar (lambda (record) (getf record :group)) shard)
                                 :test #'equal))
                  descriptors))
    (let ((manifest
            (append
             (list :format :parametric-umap-shard-manifest :version 1)
             (loop for (key value) on corpus by #'cddr
                   unless (member key '(:format :version :records))
                     append (list key value))
             (list :record-count (length records)
                   :record-limit record-limit :group-preserving t
                   :shards (nreverse descriptors)))))
      (with-open-file (stream (merge-pathnames "manifest.sexp" directory)
                              :direction :output :if-exists :supersede
                              :if-does-not-exist :create)
        (let ((*print-pretty* t) (*print-readably* t))
          (write manifest :stream stream) (terpri stream)))
      (format t "Wrote ~D records to ~D group-preserving shards in ~A.~%"
              (length records) (length packed) directory)
      manifest)))

(when *shard-corpus-run-main*
  (let ((arguments (cdr sb-ext:*posix-argv*)))
    (unless (<= 2 (length arguments) 3)
      (error "Usage: sbcl --script smc-trainer/shard-corpus.lisp CORPUS OUTPUT-DIRECTORY [RECORD-LIMIT]"))
    (shard-corpus (first arguments) (second arguments)
                  :record-limit (if (third arguments)
                                    (parse-integer (third arguments)) 25))))
