;;;; Build the standalone interactive Jicamarca UMAP HTML with SBCL.

(defparameter *umap-bundle-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defun bundle-directory ()
  *umap-bundle-directory*)

(defun bundle-path (relative)
  (merge-pathnames relative (bundle-directory)))

(defun read-whole-file (pathname)
  (with-open-file (stream pathname :direction :input)
    (with-output-to-string (output)
      (loop for character = (read-char stream nil nil)
            while character do (write-char character output)))))

(defun json-string (text)
  (with-output-to-string (output)
    (write-char #\" output)
    (loop for character across text do
      (case character
        (#\" (write-string "\\\"" output))
        (#\\ (write-string "\\\\" output))
        (t (write-char character output))))
    (write-char #\" output)))

(defun write-json-record (record stream first-record-p)
  (unless first-record-p (write-char #\, stream))
  (format stream
          "{\"c\":~A,\"t\":~,5F,\"d\":~D,\"f\":~,3F,\"o\":~,4F,\"u\":~,4F,\"s\":~,4F,\"r\":~,4F}"
          (json-string (symbol-name (getf record :event)))
          (getf record :local-time)
          (getf record :day)
          (getf record :f107)
          (getf record :observed)
          (getf record :measurement-error)
          (getf record :sf99)
          (getf record :residual)))

(defun write-page-prefix (stream)
  (format stream "<!doctype html>~%<html lang=\"en\">~%<head>~%<meta charset=\"utf-8\">~%")
  (format stream "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">~%")
  (format stream "<title>Historical Jicamarca UMAP</title>~%")
  (format stream "<style>html,body{margin:0;padding:8px;background:#fff}</style>~%</head>~%<body>~%"))

(defun safe-output-character-p (character)
  (or (alphanumericp character) (find character "-_.")))

(defun normalize-output-name (requested-name)
  (let ((name (if (and (>= (length requested-name) 5)
                       (string-equal ".html" requested-name
                                     :start2 (- (length requested-name) 5)))
                  requested-name
                  (concatenate 'string requested-name ".html"))))
    (unless (and (> (length name) 5)
                 (every #'safe-output-character-p name)
                 (not (search ".." name)))
      (error "Output name must be a safe local basename using letters, numbers, '-', '_', or '.'."))
    name))

(defun build-umap-html (&optional (requested-name "umap-hover-the-mouse-over.html"))
  (let* ((template (read-whole-file (bundle-path "src/umap-fragment.template")))
         (marker "__FEJER_DATA__")
         (marker-position (search marker template))
         (data (with-open-file (stream (bundle-path "data/observations.sexp"))
                 (read stream nil nil)))
         (records (getf data :records))
         (output-name (normalize-output-name requested-name))
         (output-path (bundle-path (concatenate 'string "output/" output-name))))
    (unless marker-position (error "Missing data marker in the HTML template."))
    (unless (= (length records) 1546)
      (error "Expected 1546 observations; found ~D." (length records)))
    (with-open-file (output output-path :direction :output :if-exists :supersede
                                         :if-does-not-exist :create)
      (write-page-prefix output)
      (write-string template output :end marker-position)
      (write-char #\[ output)
      (loop for record in records for first-record-p = t then nil do
        (write-json-record record output first-record-p))
      (write-char #\] output)
      (write-string template output :start (+ marker-position (length marker)))
      (format output "~%</body>~%</html>~%"))
    (format t "Wrote ~A with ~D observations.~%" output-path (length records))
    output-path))

(let ((arguments (cdr sb-ext:*posix-argv*)))
  (build-umap-html (if arguments (car arguments) "umap-hover-the-mouse-over.html")))
