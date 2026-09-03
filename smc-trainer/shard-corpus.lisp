;;;; Count-bounded sequential sharding at verified study-group boundaries.

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

(defun shard-map-study-groups (source function)
  "Stream one study group at a time and reject any completed group that reappears."
  (let ((completed (make-hash-table :test #'equal))
        (current-group nil) (current-split nil) (records nil))
    (labels ((finish-group ()
               (when records
                 (funcall function current-group current-split (nreverse records))
                 (setf (gethash current-group completed) t records nil))))
      (parametric-map-records
       source
       (lambda (record)
         (let ((group (getf record :group)) (split (getf record :split)))
           (cond
             ((null current-group)
              (setf current-group group current-split split))
             ((equal group current-group)
              (unless (eq split current-split)
                (error "Study group ~S crosses corpus splits." group)))
             (t
              (finish-group)
              (when (gethash group completed)
                (error "Study group ~S reappears after its completed range." group))
              (setf current-group group current-split split)))
           (push record records))))
      (finish-group))))

(defun shard-corpus (input output-directory &key (record-limit 25))
  "Partition INPUT sequentially, closing shards only between complete study groups."
  (unless (plusp record-limit) (error "Shard record limit must be positive."))
  (let* ((source (parametric-open-corpus-source input))
         (metadata (parametric-source-metadata source))
         (directory (shard-output-directory output-directory))
         (stream nil) (index 0) (shard-count 0) (total 0)
         (shard-groups nil) (descriptors nil))
    (ensure-directories-exist (merge-pathnames "manifest.sexp" directory))
    (labels
        ((close-shard ()
           (when stream
             (close stream)
             (push (list :file (format nil "shard-~6,'0D.sexp" index)
                         :records shard-count :groups (nreverse shard-groups))
                   descriptors)
             (setf stream nil shard-count 0 shard-groups nil)))
         (open-shard ()
           (incf index)
           (setf stream
                 (open (merge-pathnames (format nil "shard-~6,'0D.sexp" index)
                                        directory)
                       :direction :output :if-exists :supersede
                       :if-does-not-exist :create)))
         (write-group (group split records)
           (declare (ignore split))
           (when (and stream (> (+ shard-count (length records)) record-limit))
             (close-shard))
           (unless stream (open-shard))
           (push group shard-groups)
           (let ((*print-pretty* t) (*print-readably* t))
             (dolist (record records)
               (write record :stream stream) (terpri stream)
               (incf shard-count) (incf total)))))
      (unwind-protect
           (progn (shard-map-study-groups source #'write-group) (close-shard))
        (when stream (close stream))))
    (let ((manifest
            (append
             (list :format :parametric-umap-shard-manifest :version 1)
             (loop for (key value) on metadata by #'cddr
                   unless (member key '(:format :version :records :record-count))
                     append (list key value))
             (list :record-count total :record-limit record-limit
                   :group-preserving t :source-order :preserved
                   :shards (nreverse descriptors)))))
      (with-open-file (manifest-stream (merge-pathnames "manifest.sexp" directory)
                                       :direction :output :if-exists :supersede
                                       :if-does-not-exist :create)
        (let ((*print-pretty* t) (*print-readably* t))
          (write manifest :stream manifest-stream) (terpri manifest-stream)))
      (format t "Streamed ~D records to ~D group-preserving shards in ~A.~%"
              total index directory)
      manifest)))

(when *shard-corpus-run-main*
  (let ((arguments (cdr sb-ext:*posix-argv*)))
    (unless (<= 2 (length arguments) 3)
      (error "Usage: sbcl --script smc-trainer/shard-corpus.lisp CORPUS OUTPUT-DIRECTORY [RECORD-LIMIT]"))
    (shard-corpus (first arguments) (second arguments)
                  :record-limit (if (third arguments)
                                    (parse-integer (third arguments)) 25))))
