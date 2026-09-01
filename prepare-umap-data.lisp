;;;; Manifest-driven evidence preparation. SBCL; no Quicklisp.

(defparameter *prepare-umap-root*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(defvar *prepare-umap-run-main* t)

(load (merge-pathnames "src/evidence-windows.lisp" *prepare-umap-root*))

(defun prepare-umap-read (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil))
      (read stream nil nil))))

(defun prepare-umap-resolve-manifest (argument)
  (let ((path (pathname argument)))
    (if (pathname-type path)
        path
        (merge-pathnames "problem.sexp"
                         (pathname (concatenate 'string argument "/"))))))

(defun prepare-umap-relative-path (directory value label)
  (unless (and value (or (stringp value) (pathnamep value)))
    (error "The manifest preparation requires ~A." label))
  (merge-pathnames value directory))

(defun prepare-umap-context-key (value)
  (string-upcase (if (symbolp value) (symbol-name value)
                     (princ-to-string value))))

(defun prepare-umap-boolean (value default)
  (cond
    ((null value) nil)
    ((eq value t) t)
    ((and (symbolp value) (string= (symbol-name value) "TRUE")) t)
    ((and (symbolp value) (string= (symbol-name value) "FALSE")) nil)
    ((eq value :missing) default)
    (t (error "Expected TRUE or FALSE; found ~S." value))))

(defun prepare-umap-context-matches-p (curve-id declaration)
  (let ((ids (getf declaration :curve-ids)))
    (or (eq ids :otherwise)
        (member (prepare-umap-context-key curve-id) ids
                :test (lambda (key candidate)
                        (string= key (prepare-umap-context-key candidate)))))))

(defun prepare-umap-context (curve-id declarations)
  (or (find-if (lambda (declaration)
                 (and (not (eq (getf declaration :curve-ids) :otherwise))
                      (prepare-umap-context-matches-p curve-id declaration)))
               declarations)
      (find-if (lambda (declaration)
                 (eq (getf declaration :curve-ids) :otherwise))
               declarations)
      (error "No molecular annotation covers curve ~A." curve-id)))

(defun prepare-umap-annotate-molecular-record (record declarations)
  (let* ((context (prepare-umap-context (getf record :curve-id) declarations))
         (vector (getf context :vector)))
    (unless (and (listp vector) (every #'realp vector))
      (error "Molecular annotation for ~A has an invalid vector."
             (getf record :curve-id)))
    (setf (getf record :molecular-profile)
          (getf context :molecular-profile)
          (getf record :alteration) (getf context :alteration)
          (getf record :molecular-source) (getf context :molecular-source)
          (getf record :vector)
          (append (getf record :vector)
                  (mapcar (lambda (value) (coerce value 'double-float))
                          vector)))
    record))

(defun prepare-umap-build-records (curves preparation directory)
  (let* ((*evidence-temporal-profile-count*
           (or (getf preparation :temporal-profile-count) 10))
         (*evidence-window-widths*
           (or (getf preparation :window-widths) '(0.125d0 0.25d0 0.50d0)))
         (*evidence-survival-transform*
           (or (getf preparation :survival-transform) :identity))
         (*evidence-include-survival-progress*
           (prepare-umap-boolean
            (getf preparation :include-survival-progress :missing) t))
         (*evidence-use-typed-transforms*
           (prepare-umap-boolean
            (getf preparation :use-typed-transforms :missing) nil))
         (records (evidence-all-multiscale-records curves))
         (kind (getf preparation :kind)))
    (case kind
      (:evidence-windows records)
      (:molecular-evidence-windows
       (let* ((annotations-path
                (prepare-umap-relative-path
                 directory (getf preparation :annotations) ":ANNOTATIONS"))
              (annotations-form (prepare-umap-read annotations-path))
              (declarations (getf annotations-form :contexts)))
         (unless declarations
           (error "The molecular annotation file contains no :CONTEXTS."))
         (mapcar (lambda (record)
                   (prepare-umap-annotate-molecular-record
                    record declarations))
                 records)))
      (otherwise
       (error "Unsupported preparation kind ~S." kind)))))

(defun prepare-umap-data (manifest-name)
  (let* ((manifest-path
           (truename (prepare-umap-resolve-manifest manifest-name)))
         (directory (make-pathname :name nil :type nil
                                   :defaults manifest-path))
         (problem (prepare-umap-read manifest-path))
         (preparation
           (or (getf problem :preparation)
               (error "The manifest has no :PREPARATION section.")))
         (data (or (getf problem :data)
                   (error "The manifest has no :DATA section.")))
         (source-path
           (prepare-umap-relative-path
            directory (getf preparation :source) ":SOURCE"))
         (output-path
           (prepare-umap-relative-path
            directory (getf data :file) ":DATA :FILE"))
         (source (prepare-umap-read source-path))
         (curves (or (getf source :curves)
                     (error "The preparation source contains no :CURVES.")))
         (records (prepare-umap-build-records curves preparation directory))
         (schema (or (getf preparation :schema)
                     (error "The manifest preparation requires :SCHEMA."))))
    (ensure-directories-exist output-path)
    (with-open-file (stream output-path :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
      (let ((*print-pretty* t) (*print-circle* nil)
            (*print-length* nil) (*print-level* nil))
        (prin1 (list :schema schema :records records) stream)
        (terpri stream)))
    (format t "Manifest: ~A~%Source: ~A~%Wrote ~A with ~D records and ~D features.~%"
            manifest-path source-path output-path (length records)
            (length (getf (first records) :vector)))
    output-path))

(defun prepare-umap-main ()
  (let ((arguments (cdr *posix-argv*)))
    (unless (= (length arguments) 1)
      (error "Usage: sbcl --script prepare-umap-data.lisp MANIFEST"))
    (prepare-umap-data (first arguments))))

(when *prepare-umap-run-main*
  (prepare-umap-main))
