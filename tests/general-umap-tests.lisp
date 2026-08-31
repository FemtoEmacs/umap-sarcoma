
(defun test-root ()
  (merge-pathnames "../" (make-pathname :name nil :type nil :defaults *load-truename*)))

(defun text (path)
  (with-open-file (stream path)
    (with-output-to-string (out)
      (loop for c = (read-char stream nil nil)
            while c
            do (write-char c out)))))

(defun assert-true (condition message)
  (unless condition (error "FAIL: ~A" message))
  (format t "PASS: ~A~%" message))

(defun count-substring (needle text)
  (loop with start = 0
        for position = (search needle text :start2 start)
        while position
        do (setf start (+ position (length needle)))
        count position))

(defun sum-json-integers (marker page)
  (loop with start = 0
        for position = (search marker page :start2 start)
        while position
        for number-start = (+ position (length marker))
        for number-end = (or (position-if-not #'digit-char-p
                                               page
                                               :start number-start)
                             (length page))
        sum (parse-integer page
                           :start number-start
                           :end number-end)
        do (setf start number-end)))

(defun invalid-double-exponent-p (page)
  (loop for index from 1 below (- (length page) 2)
        thereis (and (digit-char-p (char page (1- index)))
                     (find (char page index) "dD") (find (char page (1+ index)) "+-")
                     (digit-char-p (char page (+ index 2))))))

(defun first-vector-text (page)
  (let* ((marker "\"vector\":[")
         (start (search marker page))
         (from (+ start (length marker)))
         (end (position #\] page :start from)))
    (subseq page from end)))

(defun run-build (source output)
  (let* ((root (test-root))
         (log (make-string-output-stream))
         (process
          (run-program "sbcl"
                       (list "--script"
                             (namestring (merge-pathnames "build-umap.lisp" root))
                             source output)
                       :directory root :search t :output log :error log :wait t)))
    (unless (zerop (process-exit-code process))
      (error "Build failed: ~A" (get-output-stream-string log)))))

(defun run-build-fails (source output expected)
  (let* ((root (test-root))
         (log (make-string-output-stream))
         (process
          (run-program "sbcl"
                       (list "--script"
                             (namestring
                              (merge-pathnames "build-umap.lisp" root))
                             source output)
                       :directory root :search t
                       :output log :error log :wait t))
         (message (get-output-stream-string log)))
    (assert-true (not (zerop (process-exit-code process)))
                 "malformed input is rejected")
    (assert-true (search expected message)
                 (format nil "rejection explains ~A" expected))))

(defun write-test-file (path writer)
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output
                               :if-exists :supersede
                               :if-does-not-exist :create)
    (funcall writer stream)))

(defun test-adversarial-inputs (directory)
  (let ((unsafe-csv (merge-pathnames "unsafe.csv" directory))
        (unsafe-manifest (merge-pathnames "unsafe.sexp" directory))
        (unsafe-output (merge-pathnames "unsafe.html" directory))
        (json-csv (merge-pathnames "json.csv" directory))
        (json-manifest (merge-pathnames "json.sexp" directory))
        (json-output (merge-pathnames "json.html" directory))
        (duplicate-csv (merge-pathnames "duplicate.csv" directory))
        (duplicate-manifest (merge-pathnames "duplicate.sexp" directory))
        (duplicate-output (merge-pathnames "duplicate.html" directory)))
    (write-test-file
     unsafe-csv
     (lambda (stream)
       (write-line "x" stream)
       (write-line "#.(+ 1 2)" stream)))
    (write-test-file
     unsafe-manifest
     (lambda (stream)
       (write-line
        "(:format :umap-problem :version 1 :title \"unsafe\""
        stream)
       (write-line
        " :data (:file \"unsafe.csv\" :embedding ((:field :x)))"
        stream)
       (write-line
        " :umap () :views () :tooltip ())"
        stream)))
    (run-build-fails (namestring unsafe-manifest)
                     (namestring unsafe-output)
                     "reader-dispatch syntax is forbidden")
    (write-test-file
     json-csv
     (lambda (stream)
       (write-line "id,value,label" stream)
       (write-string "a,1/3,control" stream)
       (write-char (code-char 1) stream)
       (terpri stream)))
    (write-test-file
     json-manifest
     (lambda (stream)
       (write-line
        "(:format :umap-problem :version 1 :title \"json\""
        stream)
       (write-line
        " :data (:file \"json.csv\" :id-field :id"
        stream)
       (write-line
        "        :embedding ((:field :value)))"
        stream)
       (write-line
        " :umap () :views () :tooltip ((:field :label :label \"Label\")))"
        stream)))
    (run-build (namestring json-manifest) (namestring json-output))
    (let ((page (text json-output)))
      (assert-true (not (search "\"value\":1/3" page))
                   "ratios are emitted as valid JSON numbers")
      (assert-true (search "control\\u0001" page)
                   "JSON strings escape control characters"))
    (write-test-file
     duplicate-csv
     (lambda (stream)
       (write-line "id,value" stream)
       (write-line "same,1" stream)
       (write-line "same,2" stream)))
    (write-test-file
     duplicate-manifest
     (lambda (stream)
       (write-line
        "(:format :umap-problem :version 1 :title \"duplicate\""
        stream)
       (write-line
        " :data (:file \"duplicate.csv\" :id-field :id"
        stream)
       (write-line
        "        :validation (:required-fields (:id :value)"
        stream)
       (write-line
        "                     :unique-fields (:id))"
        stream)
       (write-line
        "        :embedding ((:field :value)))"
        stream)
       (write-line
        " :umap () :views () :tooltip ())"
        stream)))
    (run-build-fails (namestring duplicate-manifest)
                     (namestring duplicate-output)
                     "duplicates ID value")))

(let* ((root (test-root))
       (output-directory (merge-pathnames "tests/tmp/general-umap/" root))
       (sexp-output
        (namestring (merge-pathnames "test-sexpr.html" output-directory)))
       (csv-output
        (namestring (merge-pathnames "test-csv.html" output-directory)))
       (transformed-output
        (namestring
         (merge-pathnames "test-D-contour-lines-sexpr.html"
                          output-directory)))
       (contour-csv-output
        (namestring
         (merge-pathnames "test-D-contour-lines-csv.html"
                          output-directory)))
       (h5ad-output
        (namestring (merge-pathnames "test-h5ad.html" output-directory))))
  (ensure-directories-exist (merge-pathnames "placeholder" output-directory))
  (let ((builder (text (merge-pathnames "build-umap.lisp" root))))
    (assert-true (not (search "/opt/homebrew/bin/h5dump" builder))
                 "H5AD reader has no machine-specific h5dump path")
    (assert-true (search "h5dump is required on PATH" builder)
                 "missing h5dump has an actionable error message"))
  (test-adversarial-inputs output-directory)
  (if (not (probe-file
            (merge-pathnames "examples/jicamarca-sexpr/problem.sexp" root)))
      (format t
              "PASS: example integration tests skipped; examples directory is intentionally empty~%GENERAL UMAP CORE TESTS PASS~%")
      (progn
  (run-build "examples/jicamarca-sexpr" sexp-output)
  (run-build "examples/jicamarca-csv" csv-output)
  (run-build "examples/D-contour-lines-sexpr" transformed-output)
  (run-build "examples/D-contour-lines-csv" contour-csv-output)
  (run-build "examples/pancreas-h5ad" h5ad-output)
  (dolist (output
           (list sexp-output csv-output transformed-output
                 contour-csv-output h5ad-output))
    (let ((page (text output)))
      (assert-true (probe-file output) (format nil "generated ~A" output))
      (assert-true (not (search "__PROBLEM__" page)) "problem marker replaced")
      (assert-true (not (search "__ROWS__" page)) "row marker replaced")
      (assert-true (not (invalid-double-exponent-p page))
       "Common Lisp double-float exponents are converted to JSON notation")
      (assert-true (search "umap-js@1.3.3" page) "UMAP dependency is pinned")))
  (assert-true (search "Historical Jicamarca" (text sexp-output))
   "S-expression example loaded")
  (assert-true (search "Historical Jicamarca" (text csv-output)) "CSV example loaded")
  (assert-true
   (search "Jicamarca density contours (S-expression)"
           (text transformed-output))
   "Jicamarca S-expression density-contour manifest loaded")
  (assert-true
   (search "Jicamarca density contours (CSV)" (text contour-csv-output))
   "Jicamarca CSV density-contour manifest loaded")
  (assert-true (= (count-substring "\"vector\":["
                                    (text contour-csv-output))
                  2334)
               "CSV contour representation creates the same 2334 profiles")
  (assert-true
   (search "\"density_surface\":true" (text contour-csv-output))
   "CSV contour representation enables density surfaces")
  (assert-true (= (count-substring "\"vector\":["
                                    (text transformed-output))
                  2334)
               "multiscale representation creates 2334 local-time profiles")
  (assert-true (= (sum-json-integers "\"observations\":"
                                     (text transformed-output))
                  43222)
               "multiscale windows contain 43222 measurement memberships")
  (assert-true
   (and (= (count-substring "\"window_width\":2.0e0"
                            (text transformed-output))
           477)
        (= (count-substring "\"window_width\":3.0e0"
                            (text transformed-output))
           544)
        (= (count-substring "\"window_width\":4.0e0"
                            (text transformed-output))
           599)
        (= (count-substring "\"window_width\":6.0e0"
                            (text transformed-output))
           714))
   "local-time profiles record all four window scales")
  (assert-true (search "\"observations\":8" (text transformed-output))
               "minimum accepted window contains eight measurements")
  (assert-true (= (1+ (count #\, (first-vector-text (text transformed-output))))
                  15)
               "window profile contains 15 physical, contextual, and scale features")
  (assert-true
   (search "\"density_surface\":true,\"density_bandwidth\":24"
           (text transformed-output))
   "Jicamarca enables density-surface rendering")
  (assert-true
   (search "\"density_thresholds\":12,\"density_opacity\":0.2e0"
           (text transformed-output))
   "Jicamarca configures twelve darker density levels")
  (assert-true
   (search "\"density_color\":\"data\",\"density_color_bands\":7"
           (text transformed-output))
   "Jicamarca density colors follow the selected data colors")
  (assert-true
   (search "\"point_radius\":6,\"point_opacity\":0.0e0"
           (text transformed-output))
   "Jicamarca keeps invisible hover targets without large circles")
  (assert-true
   (search "\"center_point_radius\":3,\"center_point_opacity\":1.0e0"
           (text transformed-output))
   "Jicamarca uses opaque three-pixel centers")
  (assert-true
   (search "\"center_point_every\":3"
           (text transformed-output))
   "Jicamarca displays every third point in its data color")
  (assert-true (search "Pancreas single-cell" (text h5ad-output))
   "H5AD example loaded")
  (let ((h5ad-page (text h5ad-output)))
    (assert-true (not (search "\"center_point_radius\"" h5ad-page))
                 "pancreas keeps the default single-circle rendering")
    (assert-true
     (search "\"density_surface\":true,\"density_bandwidth\":24"
             h5ad-page)
     "pancreas enables density-surface rendering")
    (assert-true
     (search "\"density_color\":\"data\",\"density_color_bands\":7"
             h5ad-page)
     "pancreas density colors follow the selected data colors")
    (assert-true (= (count-substring "\"vector\":[" h5ad-page) 1132)
                 "raw-expression filtering retains 1132 pancreas cells")
    (assert-true (search "\"genes_expressed\":264" h5ad-page)
                 "first CSR row contains 264 expressed genes")
    (assert-true (not (search "\"genes_expressed\":null" h5ad-page))
                 "selected pancreas cells have numerical gene counts")
    (assert-true (not (search "\"genes_expressed\":\"NAN\"" h5ad-page))
                 "H5AD NaN tokens are absent from gene counts"))
  (format t "GENERAL UMAP TESTS PASS~%"))))
