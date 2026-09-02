;;;; Place a new feature vector in the fixed learned UMAP atlas.

(defparameter *parametric-predict-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))
(unless (fboundp 'parametric-forward)
  (load (merge-pathnames "transformer.lisp" *parametric-predict-directory*)))

(defvar *parametric-predict-run-main* t)

(defun predict-read-form (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil)) (read stream))))

(defun standardize-raw-features (values preprocessing)
  (let ((means (getf preprocessing :means)) (scales (getf preprocessing :scales)))
    (unless (= (length values) (length means) (length scales))
      (error "Expected ~D raw feature values, received ~D."
             (length means) (length values)))
    (loop for value in values for mean in means for scale in scales
          collect (/ (- (coerce value 'double-float) mean) scale))))

(defun predict-from-artifact (artifact raw-values)
  (unless (and (eq (getf artifact :format) :trained-parametric-umap)
               (= (getf artifact :version) 1))
    (error "Unsupported trained Parametric UMAP artifact."))
  (parametric-predict
   (form-parametric-model (getf artifact :model))
   (standardize-raw-features raw-values (getf artifact :preprocessing))))

(when *parametric-predict-run-main*
  (let ((arguments (cdr sb-ext:*posix-argv*)))
    (unless (= (length arguments) 2)
      (error "Usage: sbcl --script smc-trainer/predict.lisp WEIGHTS '(VALUE ...)'"))
    (let* ((artifact (predict-read-form (first arguments)))
           (values (let ((*read-eval* nil)) (read-from-string (second arguments))))
           (coordinates (predict-from-artifact artifact values)))
      (let ((*print-readably* t))
        (write (list :coordinates coordinates
                     :coordinate-system :winning-common-lisp-umap))
        (terpri)))))
