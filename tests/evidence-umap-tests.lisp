;;;; Pilot evidence UMAP tests. Run from repository root.

(load "src/evidence-windows.lisp")

(defun pilot-read (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil)) (read stream))))

(defun pilot-assert (condition message)
  (unless condition (error "FAIL: ~A" message))
  (format t "PASS: ~A~%" message))

(let* ((source (pilot-read "data/pilot-landmarks.sexp"))
       (curves (getf source :curves))
       (records (evidence-all-multiscale-records curves))
       (types (remove-duplicates
               (mapcar (lambda (record) (getf record :sarcoma-type)) records)
               :test #'string=)))
  (pilot-assert (= 20 (length curves)) "twenty pilot evidence curves or strata")
  (pilot-assert (= 600 (length records))
                "ten anchors at three scales per evidence curve")
  (pilot-assert (= 4 (length types)) "four requested sarcoma types")
  (pilot-assert (every (lambda (record) (= 23 (length (getf record :vector))))
                       records)
                "all mixed embedding vectors have 23 continuous dimensions")
  (pilot-assert (= 0.8d0 (evidence-transform-survival 0.8d0))
                "survival coordinates remain on the raw probability scale")
  (pilot-assert
   (and (< (getf (find 'sts-local-1999-2004 curves
                        :key (lambda (curve) (getf curve :id)))
                  :survival-progress-delta)
           0d0)
        (> (getf (find 'gist-distant-2012-2019 curves
                        :key (lambda (curve) (getf curve :id)))
                  :survival-progress-delta)
           0d0))
   "survival progress preserves decline and improvement signs")
  (pilot-assert
   (every (lambda (record)
            (every (lambda (value) (and (numberp value) (= value value)))
                   (getf record :vector)))
          records)
   "all embedding features are finite numbers")
  (pilot-assert
   (every (lambda (curve)
            (let ((points (evidence-curve-points curve 41)))
              (loop for left in points for right in (cdr points)
                    always (>= (second left) (second right)))))
          curves)
   "all evidence curves are monotone")
  (format t "PILOT EVIDENCE UMAP TESTS PASS~%"))
