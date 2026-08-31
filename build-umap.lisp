;;;; General manifest-driven UMAP page builder. SBCL; no Quicklisp.

(defparameter *script-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defun read-form-file (path)
  (with-open-file (s path)
    (let ((*read-eval* nil))
      (read s nil nil))))

(defun file-text (path)
  (with-open-file (s path)
    (with-output-to-string (o)
      (loop for c = (read-char s nil nil)
            while c
            do (write-char c o)))))

(defun trim (x) (string-trim '(#\  #\Tab #\Newline #\Return) x))

(defun split-string (text delimiter)
  (loop with start = 0
        for
        end = (position delimiter text :start start)
        collect (subseq text start end)
        while
        end
        do (setf start (1+ end))))

(defun csv-row (line)
  (loop with fields = nil
        with field = ""
        with quoted = nil
        with i = 0
        while (< i (length line))
        for c = (char line i)
        do (cond
            ((char= c #\")
             (if (and quoted (< (1+ i) (length line))
		      (char= (char line (1+ i)) #\"))
                 (progn (setf field (concatenate 'string field "\""))
			(incf i))
                 (setf quoted (not quoted))))
            ((and (char= c #\,) (not quoted))
	     (push field fields) (setf field ""))
            (t (setf field (concatenate 'string field (string c)))))
	          (incf i)
        finally (return (nreverse (cons field fields)))))

(defun field-key (x) (intern (string-upcase (substitute #\- #\_ (trim x)))
			     :keyword))

(defun scalar (x)
  (let ((v (trim x)))
    (cond ((or (string-equal v "true") (string-equal v "t")) t)
          ((or (string-equal v "false")
               (string-equal v "nil")
               (string= v ""))
           nil)
          ((find #\# v)
           (error "CSV reader-dispatch syntax is forbidden in cell ~S." v))
          ((not (every (lambda (character)
                         (find character "0123456789+-./eEdD"))
                       v))
           v)
          (t
           (handler-case
               (let ((*read-eval* nil)
                     (*package* (find-package :keyword))
                     (end (list :end)))
                 (multiple-value-bind (value position)
                     (read-from-string v nil end)
                   (if (and (not (eq value end))
                            (= position (length v))
                            (or (numberp value)
                                (eq value t)
                                (null value)))
                       value
                       v)))
             (error (condition)
               (error "Invalid CSV cell ~S: ~A" v condition)))))))

(defun read-csv-records (path)
  (with-open-file (s path)
    (let ((headers (mapcar #'field-key (csv-row (read-line s)))) records)
      (loop for line = (read-line s nil nil)
            while line
            unless (string= (trim line) "")
            do (push
                (loop for key in headers
                      for value in (csv-row line)
                      append (list key (scalar value)))
                records))
      (nreverse records))))

(defun extension (path) (string-downcase (or (pathname-type path) "")))

(defun h5dump-output (file dataset)
  (let ((out (make-string-output-stream)))
    (let ((p
           (handler-case
               (run-program "h5dump"
                            (list "-d" dataset "-y" "-w" "0"
                                  (namestring file))
                            :search t :output out :error out :wait t)
             (error (condition)
               (error "h5dump is required on PATH to read H5AD files: ~A"
                      condition)))))
      (unless (zerop (process-exit-code p))
        (error "h5dump failed for ~A: ~A" dataset
	       (get-output-stream-string out)))
      (get-output-stream-string out))))

(defun data-body (dump)
  (let* ((marker "   DATA {")
         (start (search marker dump))
         (from (and start (+ start (length marker))))
         (end (and from (search (format nil "~%   }") dump :start2 from))))
    (unless (and from end) (error "Cannot locate HDF5 DATA block."))
    (subseq dump from end)))

(defun parse-h5-values (dump)
  (let ((body (data-body dump)) values)
    (if (find #\" body)
        (loop with i = 0
              for open = (position #\" body :start i)
              while open
              for close = (position #\" body :start (1+ open))
              do (push (subseq body (1+ open) close) values)
	      (setf i (1+ close)))
        (dolist (part (split-string body #\,))
          (let ((v (trim part)))
            (unless (string= v "")
              (push (if (member v '("nan" "-nan" "inf" "-inf")
                                :test #'string-equal)
                        nil
                        (read-from-string v))
                    values)))))
    (nreverse values)))

(load (merge-pathnames "src/raw-csr-pca.lisp" *script-directory*))
(load (merge-pathnames "src/profile-representation.lisp" *script-directory*))

(defun csr-nonzero-counts (path dataset)
  (let ((pointers (parse-h5-values (h5dump-output path dataset))))
    (loop for left in pointers
          for right in (cdr pointers)
          collect (- right left))))

(defun read-h5ad-records (path spec)
  (let ((embedding (getf spec :embedding)))
    (multiple-value-bind (vectors selected)
        (if (eq (getf embedding :kind) :raw-csr-pca)
            (raw-csr-pca path embedding)
            (let* ((columns (or (getf embedding :columns) 2))
                   (flat
                    (parse-h5-values
                     (h5dump-output path (getf embedding :dataset))))
                   (count (/ (length flat) columns)))
              (values
               (loop for index below count collect
                 (subseq flat (* index columns) (* (1+ index) columns)))
               (loop for index below count collect index))))
      (let ((records
             (loop for vector in vectors
                   for original in selected
                   collect (list :id original :vector vector))))
        (dolist (field (getf spec :fields))
          (let* ((name (getf field :name))
                 (dataset (getf field :dataset))
                 (kind (getf field :kind))
                 (all-values
                  (cond
                    ((eq kind :categorical)
                     (let ((categories
                            (parse-h5-values
                             (h5dump-output
                              path
                              (concatenate 'string dataset "/categories"))))
                           (codes
                            (parse-h5-values
                             (h5dump-output
                              path
                              (concatenate 'string dataset "/codes")))))
                       (mapcar (lambda (code) (nth code categories)) codes)))
                    ((eq kind :csr-nonzero-count)
                     (csr-nonzero-counts path dataset))
                    (t
                     (parse-h5-values (h5dump-output path dataset)))))
                 (value-vector (coerce all-values 'vector))
                 (values
                  (mapcar (lambda (index) (aref value-vector index)) selected)))
            (setf records
                  (loop for record in records
                        for value in values
                        collect (append record (list name value))))))
        (let ((maximum (getf (getf spec :selection) :maximum)))
          (if (and maximum (< maximum (length records)))
              (subseq records 0 maximum)
              records))))))

(defun tabular-median (numbers)
  (let* ((sorted (sort (copy-seq numbers) #'<))
         (size (length sorted))
         (middle (floor size 2)))
    (if (oddp size)
        (nth middle sorted)
        (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2d0))))

(defun tabular-transform-values (records field)
  (mapcar (lambda (record) (getf record field)) records))

(defun tabular-transform-center (request values)
  (cond ((numberp request) request)
        ((eq request :median) (tabular-median values))
        ((null request) 0d0)
        (t (error "Unsupported transform center ~A." request))))

(defun tabular-transform-scale (request values center)
  (let ((scale
         (cond ((numberp request) request)
               ((eq request :median) (tabular-median values))
               ((eq request :mad)
                (tabular-median
                 (mapcar (lambda (value) (abs (- value center))) values)))
               ((null request) 1d0)
               (t (error "Unsupported transform scale ~A." request)))))
    (if (zerop scale) 1d0 scale)))

(defun fit-tabular-transform (records item)
  (let* ((field (getf item :field))
         (transform (getf item :transform))
         (kind (and (consp transform) (getf transform :kind))))
    (if (member kind '(:asinh :log1p :symlog))
        (let* ((values (tabular-transform-values records field))
               (center
                (tabular-transform-center (getf transform :center) values))
               (scale
                (tabular-transform-scale
                 (getf transform :scale) values center)))
          (list :field field :transform
                (list :kind kind :center center :scale scale)))
        item)))

(defun fit-tabular-embedding (records embedding)
  (mapcar (lambda (item) (fit-tabular-transform records item)) embedding))

(defun transformed-tabular-value (value transform)
  (let ((kind (and (consp transform) (getf transform :kind))))
    (cond
      ((eq kind :asinh)
       (asinh (/ (- value (getf transform :center))
                 (getf transform :scale))))
      ((eq kind :log1p)
       (when (minusp value)
         (error "LOG1P transform requires nonnegative values; found ~A." value))
       (log (1+ (/ value (getf transform :scale)))))
      ((eq kind :symlog)
       (let* ((centered (/ (- value (getf transform :center))
                           (getf transform :scale)))
              (magnitude (log (1+ (abs centered)) 10d0)))
         (if (minusp centered) (- magnitude) magnitude)))
      (t value))))

(defun record-vector (record embedding)
  (loop for item in embedding
        append (let* ((field (getf item :field))
                      (value (getf record field))
                      (transform (getf item :transform)))
                 (cond
                   ((and (consp transform)
                         (eq (car transform) :circular))
                   (let ((angle (* 2 pi (/ value (cadr transform)))))
                      (list (sin angle) (cos angle))))
                   ((and (listp value) (null transform)) value)
                   (t
                    (list (transformed-tabular-value value transform)))))))

(defun record-has-field-p (record field)
  (loop for tail on record by #'cddr
        thereis (eq (car tail) field)))

(defun validate-required-fields (records fields)
  (loop for record in records
        for index from 0 do
    (dolist (field fields)
      (unless (record-has-field-p record field)
        (error "Record ~D is missing required field ~A." index field)))))

(defun validate-unique-fields (records fields)
  (dolist (field fields)
    (let (seen)
      (loop for record in records
            for index from 0
            for value = (getf record field) do
        (when (member value seen :test #'equal)
          (error "Record ~D duplicates ~A value ~S." index field value))
        (push value seen)))))

(defun validate-ranges (records ranges)
  (dolist (range ranges)
    (let ((field (getf range :field))
          (minimum (getf range :minimum))
          (maximum (getf range :maximum)))
      (loop for record in records
            for index from 0
            for value = (getf record field) do
        (unless (numberp value)
          (error "Record ~D field ~A is not numeric: ~S."
                 index field value))
        (when (and minimum (< value minimum))
          (error "Record ~D field ~A is below ~A: ~A."
                 index field minimum value))
        (when (and maximum (> value maximum))
          (error "Record ~D field ~A is above ~A: ~A."
                 index field maximum value))))))

(defun category-text (value)
  (string-upcase
   (if (symbolp value) (symbol-name value) (princ-to-string value))))

(defun same-category-p (left right)
  (string= (category-text left) (category-text right)))

(defun validate-category-values (records declarations)
  (dolist (declaration declarations)
    (let* ((field (getf declaration :field))
           (expected (getf declaration :values))
           (actual (remove-duplicates
                    (mapcar (lambda (record) (getf record field)) records)
                    :test #'same-category-p)))
      (dolist (value expected)
        (unless (member value actual :test #'same-category-p)
          (error "Declared ~A value ~S has no records." field value)))
      (dolist (value actual)
        (unless (member value expected :test #'same-category-p)
          (error "Undeclared ~A value ~S occurs in the data." field value))))))

(defun validate-records (records validation)
  (when validation
    (unless records (error "Dataset contains no records."))
    (validate-required-fields records (getf validation :required-fields))
    (validate-unique-fields records (getf validation :unique-fields))
    (validate-ranges records (getf validation :ranges))
    (validate-category-values
     records (getf validation :category-values)))
  records)

(defun read-tabular-records (path spec)
  (let* ((raw
          (if (string= (extension path) "csv")
              (read-csv-records path)
              (getf (read-form-file path)
		    (or (getf spec :records-key) :records))))
         (validated (validate-records raw (getf spec :validation)))
         (profile (getf spec :profile))
         (id-field (getf spec :id-field))
         (embedding (and (not profile)
                         (fit-tabular-embedding raw (getf spec :embedding))))
         (records (if profile
                      (profile-records validated profile)
                      validated)))
    (loop for record in records
          for i from 0 collect
      (if profile
          record
          (append
           (list :id (or (and id-field (getf record id-field)) i)
                 :vector (record-vector record embedding))
           record)))))

(defun read-dataset (path spec)
  (cond
    ((member (extension path) '("sexp" "sexpr" "csv") :test #'string=)
     (read-tabular-records path spec))
    ((string= (extension path) "h5ad")
     (validate-records
      (read-h5ad-records path spec)
      (getf spec :validation)))
    (t
     (error "Unsupported .~A data file; supported: csv, sexp/sexpr, h5ad."
            (extension path)))))

(defun json-key (key)
  (string-downcase (substitute #\_ #\- (symbol-name key))))

(defun json-number-text (number)
  (cond
    ((integerp number) (format nil "~D" number))
    ((rationalp number) (json-number-text (coerce number 'double-float)))
    ((floatp number)
     (unless (= number number)
       (error "JSON cannot represent NaN."))
     (let ((text (format nil "~A" number)))
       (substitute #\e #\D (substitute #\e #\d text))))
    (t (error "Unsupported JSON number ~S." number))))

(defun write-json-string (x s)
  (write-char #\" s)
  (loop for c across (princ-to-string x)
        do (case c
             (#\" (write-string "\\\"" s))
             (#\\ (write-string "\\\\" s))
             (#\Newline (write-string "\\n" s))
             (#\Return (write-string "\\r" s))
             (#\Tab (write-string "\\t" s))
             (t
              (if (< (char-code c) #x20)
                  (format s "\\u~4,'0X" (char-code c))
                  (write-char c s)))))
  (write-char #\" s))

(defun write-json (value s)
  (cond ((null value) (write-string "null" s))
	((eq value t) (write-string "true" s))
        ((numberp value) (write-string (json-number-text value) s))
        ((stringp value) (write-json-string value s))
        ((keywordp value) (write-json-string (json-key value) s))
        ((and (listp value) (not (keywordp (car value))))
	 (write-char #\[ s)
         (loop for item in value
               for first = t then nil
               do (unless first (write-char #\, s))
	       (write-json item s))
         (write-char #\] s))
        ((listp value) (write-char #\{ s)
         (loop for (key item) on value by #'cddr
               for first = t then nil
               do (unless first
                    (write-char #\, s))
	             (write-json-string
                      (json-key key) s)
	       (write-char #\: s) (write-json item s))
         (write-char #\} s))
        (t (write-json-string value s))))

(defun replace-marker (text marker replacement)
  (let ((p (search marker text)))
    (unless p (error "Missing template marker ~A." marker))
    (concatenate 'string (subseq text 0 p) replacement
                 (subseq text (+ p (length marker))))))

(defun resolve-manifest (argument)
  (let ((path (pathname argument)))
    (if (pathname-type path)
        path
        (merge-pathnames "problem.sexp"
             (pathname (concatenate 'string argument "/"))))))

(defun build-umap-html (manifest-name output-name)
  (let* ((manifest-path (truename (resolve-manifest manifest-name)))
         (directory (make-pathname :name nil :type nil :defaults
				   manifest-path))
         (problem (read-form-file manifest-path))
         (spec (getf problem :data))
         (data-path (merge-pathnames (getf spec :file) directory))
         (rows (read-dataset data-path spec))
         (template
          (file-text (merge-pathnames "src/general-umap.template"
				      *script-directory*)))
         (config (with-output-to-string (s) (write-json problem s)))
         (payload (with-output-to-string (s) (write-json rows s)))
         (page
          (replace-marker (replace-marker template
			        "__PROBLEM__" config)
			  "__ROWS__"
			   payload))
         (output (pathname output-name)))
    (ensure-directories-exist output)
    (with-open-file
        (s output :direction :output :if-exists :supersede
	   :if-does-not-exist :create)
      (write-string page s))
    (format t "Wrote ~A from ~A (~D rows, .~A reader).~%"
	    output manifest-path
            (length rows) (extension data-path))
    output))

(defun main ()
  (let ((args (cdr *posix-argv*)))
    (unless (= (length args) 2)
      (error
       "Usage: sbcl --script build-umap.lisp PROBLEM-DIRECTORY-OR-FILE OUTPUT.html"))
    (build-umap-html (first args) (second args))))

(main)
