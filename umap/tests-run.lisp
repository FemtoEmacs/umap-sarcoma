(defun test-directory ()
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defun test-root ()
  (merge-pathnames "../" (test-directory)))

(defun read-file-text (pathname)
  (with-open-file (stream pathname :direction :input)
    (with-output-to-string (output)
      (loop for character = (read-char stream nil nil)
            while character do (write-char character output)))))

(defun count-substring (needle text)
  (loop with start = 0
        for position = (search needle text :start2 start)
        while position
        do (setf start (+ position (length needle)))
        count position))

(defun assert-true (condition description)
  (unless condition (error "FAIL: ~A" description))
  (format t "PASS: ~A~%" description))

(load (merge-pathnames "build-umap.lisp" (test-root)))

(let* ((output-path (merge-pathnames "output/umap-hover-the-mouse-over.html" (test-root)))
       (text (read-file-text output-path)))
  (assert-true (probe-file output-path) "generated HTML exists")
  (assert-true (search "Historical Jicamarca covariate neighborhoods" text)
               "title is present")
  (assert-true (not (search "__FEJER_DATA__" text)) "data marker was replaced")
  (assert-true (= (count-substring "{\"c\":" text) 1546)
               "all 1546 records are embedded")
  (assert-true (search "umap-js@1.3.3" text) "UMAP version is pinned")
  (assert-true (search "d3@7.9.0" text) "D3 version is pinned")
  (format t "REPRODUCTION TESTS PASS~%"))

(let ((custom-path (build-umap-html "coworker-test-map")))
  (assert-true (string-equal "coworker-test-map.html" (file-namestring custom-path))
               "custom output name receives .html suffix")
  (assert-true (probe-file custom-path) "custom-named HTML exists"))

(assert-true
 (handler-case (progn (build-umap-html "../unsafe") nil)
   (error () t))
 "unsafe path-like output name is rejected")
