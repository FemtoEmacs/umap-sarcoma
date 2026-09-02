(defparameter *parametric-tests-root*
  (merge-pathnames "../" (make-pathname :name nil :type nil :defaults *load-truename*)))

(load (merge-pathnames "smc-trainer/transformer.lisp" *parametric-tests-root*))
(defparameter *parametric-predict-run-main* nil)
(load (merge-pathnames "smc-trainer/predict.lisp" *parametric-tests-root*))

(test-cases:deftest automatic-differentiation-product-gradient
  (let* ((x (make-ad-node 3.0d0 :parameter-p t))
         (square (ad* x x)))
    (ad-backpropagate square)
    (test-cases:check (< (abs (- (ad-gradient x) 6.0d0)) 1.0d-12))))

(test-cases:deftest explicit-transformer-architecture
  (let* ((model (initialize-parametric-model 6 :d-model 8 :d-ff 12))
         (input '(0.1d0 -0.2d0 0.3d0 -0.4d0 0.5d0 -0.6d0))
         (tokens (transformer-feature-tokens model input))
         (attention (transformer-self-attention model tokens))
         (encoded (transformer-block model tokens))
         (coordinates (transformer-forward model input)))
    (test-cases:check (fboundp 'transformer-self-attention))
    (test-cases:check (fboundp 'transformer-feed-forward))
    (test-cases:check (fboundp 'transformer-block))
    (test-cases:check (fboundp 'transformer-forward))
    (test-cases:check-equal 6 (length tokens))
    (test-cases:check-equal 6 (length attention))
    (test-cases:check-equal 6 (length encoded))
    (test-cases:check (every (lambda (token) (= 8 (length token))) encoded))
    (test-cases:check-equal 2 (length coordinates))))

(test-cases:deftest one-observation-overfit-and-roundtrip
  (let* ((corpus-path (merge-pathnames
                       "smc-trainer/corpus/pilot-parametric-umap.sexp"
                       *parametric-tests-root*))
         (weights-path (merge-pathnames
                        "smc-trainer/weights/one-observation.sexp"
                        *parametric-tests-root*))
         (corpus (with-open-file (stream corpus-path)
                   (let ((*read-eval* nil)) (read stream))))
         (record (first (getf corpus :records)))
         (input (getf record :input)) (target (getf record :target))
         (model (initialize-parametric-model (length input))))
    (multiple-value-bind (trained initial-loss final-loss)
        (train-one-observation model input target :epochs 600 :learning-rate 0.01d0)
      (test-cases:check (< final-loss (* initial-loss 1.0d-4))
                        "one-record loss should fall by at least four orders of magnitude")
      (test-cases:check (< final-loss 1.0d-6) "one-record fit should be numerically close")
      (save-parametric-model trained weights-path)
      (let ((before (parametric-predict trained input))
            (after (parametric-predict (load-parametric-model weights-path) input)))
        (loop for left in before for right in after do
          (test-cases:check (< (abs (- left right)) 1.0d-12)
                            "serialized model must preserve prediction"))))))

(test-cases:deftest fitted-artifact-predicts-from-raw-features
  (let* ((artifact (predict-read-form
                    (merge-pathnames
                     "smc-trainer/weights/pilot-coordinate-baseline.sexp"
                     *parametric-tests-root*)))
         (preprocessing (getf artifact :preprocessing))
         (means (getf preprocessing :means))
         (coordinates (predict-from-artifact artifact means)))
    (test-cases:check-equal :full-backpropagation
                            (getf (getf artifact :model) :training))
    (test-cases:check-equal 2 (length coordinates))
    (test-cases:check
     (every (lambda (value)
              (and (realp value) (= value value)
                   (< (abs value) most-positive-double-float)))
            coordinates))))
