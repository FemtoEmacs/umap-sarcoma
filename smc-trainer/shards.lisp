;;;; Streaming access to single-file and sharded Parametric UMAP corpora.

(defparameter *parametric-shard-end* (list :end-of-parametric-shard))

(defun parametric-read-one-form (path)
  (with-open-file (stream path :direction :input)
    (let ((*read-eval* nil)) (read stream))))

(defun parametric-open-corpus-source (path)
  (let ((form (parametric-read-one-form path)))
    (cond
      ((eq (getf form :format) :parametric-umap-corpus)
       (list :kind :single :path path :metadata form))
      ((eq (getf form :format) :parametric-umap-shard-manifest)
       (list :kind :shards :path path :metadata form))
      (t (error "Unsupported Parametric UMAP corpus source ~A." path)))))

(defun parametric-source-metadata (source)
  (getf source :metadata))

(defun parametric-manifest-directory (source)
  (make-pathname :name nil :type nil :defaults (pathname (getf source :path))))

(defun parametric-map-shard-file (path function)
  (with-open-file (stream path :direction :input)
    (let ((*read-eval* nil))
      (loop for record = (read stream nil *parametric-shard-end*)
            until (eq record *parametric-shard-end*)
            do (funcall function record)))))

(defun parametric-map-records (source function &key split)
  "Call FUNCTION for each record, reading shards one at a time."
  (flet ((accept (record)
           (when (or (null split) (eq split (getf record :split)))
             (funcall function record))))
    (if (eq (getf source :kind) :single)
        (dolist (record (getf (parametric-source-metadata source) :records))
          (accept record))
        (dolist (descriptor (getf (parametric-source-metadata source) :shards))
          (parametric-map-shard-file
           (merge-pathnames (getf descriptor :file)
                            (parametric-manifest-directory source))
           #'accept)))))

(defun parametric-count-records (source &key split)
  (let ((count 0))
    (parametric-map-records source (lambda (record) (declare (ignore record))
                                    (incf count))
                            :split split)
    count))

(defun parametric-first-record (source &key split)
  (let ((first nil))
    (parametric-map-records source (lambda (record) (unless first (setf first record)))
                            :split split)
    first))
