(defparameter *parametric-tests-root*
  (merge-pathnames "../" (make-pathname :name nil :type nil :defaults *load-truename*)))

(load (merge-pathnames "smc-trainer/transformer.lisp" *parametric-tests-root*))
(load (merge-pathnames "smc-trainer/shards.lisp" *parametric-tests-root*))
(defparameter *parametric-predict-run-main* nil)
(load (merge-pathnames "smc-trainer/predict.lisp" *parametric-tests-root*))

(test-cases:deftest automatic-differentiation-product-gradient
  (let* ((x (make-ad-node 3.0d0 :parameter-p t))
         (square (ad* x x)))
    (ad-backpropagate square)
    (test-cases:check (< (abs (- (ad-gradient x) 6.0d0)) 1.0d-12))))

(test-cases:deftest multi-head-multi-layer-transformer-architecture
  (let* ((model (initialize-parametric-model 6 :d-model 8 :d-ff 12
                                             :num-heads 2 :num-layers 2))
         (input '(0.1d0 -0.2d0 0.3d0 -0.4d0 0.5d0 -0.6d0))
         (tokens (transformer-feature-tokens model input))
         (encoded (transformer-encoder-stack model tokens))
         (coordinates (transformer-forward model input)))
    (test-cases:check-equal :multi-head-stack (parametric-model-kind model))
    (test-cases:check-equal 2 (parametric-model-num-heads model))
    (test-cases:check-equal 2 (parametric-model-num-layers model))
    (test-cases:check (arrayp (parametric-model-feature-embeddings model)))
    ;; Two layers, two heads per layer, each head projecting to D-MODEL/2 = 4.
    (test-cases:check (arrayp (parametric-model-layer-heads-wq model)))
    (test-cases:check-equal 2 (length (parametric-model-layer-heads-wq model)))
    (test-cases:check-equal 2 (length (aref (parametric-model-layer-heads-wq model) 0)))
    (test-cases:check-equal 4 (length (aref (aref (parametric-model-layer-heads-wq model) 0) 0)))
    (test-cases:check-equal
     8 (length (aref (aref (aref (parametric-model-layer-heads-wq model) 0) 0) 0))
     :description "each head's WQ row has D-MODEL columns")
    (test-cases:check-equal 2 (length (parametric-model-layer-wo model)))
    (test-cases:check-equal 2 (length (parametric-model-layer-attention-gain model)))
    (test-cases:check-equal 8 (length (aref (parametric-model-layer-attention-gain model) 0)))
    (test-cases:check-equal 8 (length (parametric-model-final-norm-gain model)))
    (test-cases:check (arrayp tokens))
    (test-cases:check (every #'arrayp tokens))
    (test-cases:check (arrayp encoded))
    (test-cases:check (arrayp coordinates))
    (test-cases:check (fboundp 'transformer-multihead-attention))
    (test-cases:check (fboundp 'transformer-feed-forward-layer))
    (test-cases:check (fboundp 'transformer-encoder-layer))
    (test-cases:check (fboundp 'transformer-encoder-stack))
    (test-cases:check (fboundp 'transformer-forward))
    (test-cases:check-equal 6 (length tokens))
    (test-cases:check-equal 6 (length encoded))
    (test-cases:check (every (lambda (token) (= 8 (length token))) encoded))
    (test-cases:check-equal 2 (length coordinates))
    (test-cases:check
     (every (lambda (v) (let ((x (ad-value v))) (and (realp x) (= x x)))) coordinates)
     "coordinates must be finite reals, not NaN")))

(test-cases:deftest attention-head-count-must-divide-d-model
  (test-cases:check-signals error
    (initialize-parametric-model 3 :d-model 8 :d-ff 4 :num-heads 3 :num-layers 1)))

;; A hand-written, minimal :VERSION 1 saved-model form, in the exact shape
;; produced by the original single-head, single-block implementation before
;; this file introduced multi-head, multi-layer models. Existing on-disk
;; artifacts (trained before this change) have this same shape, so this
;; fixture stands in for one without depending on any generated weight file.
(defparameter *legacy-v1-test-form*
  '(:format :parametric-feature-transformer :version 1
    :training :full-backpropagation :seed 1
    :feature-count 2 :d-model 2 :d-ff 2
    :parameters
    (((0.1d0 0.2d0) (0.3d0 0.4d0))    ; feature-embeddings: 2 features x 2 dims
     (0.1d0 -0.1d0)                   ; scalar-weights
     (0.0d0 0.0d0)                    ; scalar-bias
     ((0.2d0 -0.1d0) (0.1d0 0.3d0))   ; wq
     ((0.1d0 0.1d0) (-0.2d0 0.2d0))   ; wk
     ((0.3d0 -0.2d0) (0.1d0 0.1d0))   ; wv
     ((0.2d0 0.1d0) (-0.1d0 0.2d0))   ; wo
     ((0.1d0 -0.1d0) (0.2d0 0.2d0))   ; w1 (d-ff x d-model)
     (0.0d0 0.0d0)                    ; b1
     ((0.1d0 0.2d0) (-0.1d0 0.1d0))   ; w2 (d-model x d-ff)
     (0.0d0 0.0d0)                    ; b2
     ((0.1d0 0.2d0) (0.3d0 -0.1d0))   ; output-weights (2 x d-model)
     (0.0d0 0.0d0))))                 ; output-bias

(test-cases:deftest legacy-version-1-model-loads-and-predicts
  (let* ((model (form-parametric-model *legacy-v1-test-form*))
         (input '(0.5d0 -0.3d0))
         (coordinates (parametric-predict model input)))
    (test-cases:check-equal :legacy-single-head (parametric-model-kind model))
    (test-cases:check-equal 1 (parametric-model-num-heads model))
    (test-cases:check-equal 1 (parametric-model-num-layers model))
    (test-cases:check-equal 2 (length coordinates))
    (test-cases:check (every (lambda (v) (and (realp v) (= v v))) coordinates)
                      "legacy prediction must be finite reals, not NaN")
    ;; A legacy model must reserialize as VERSION 1 with its parameters
    ;; byte-for-byte preserved, so an already-deployed artifact keeps
    ;; loading and predicting exactly as before, without retraining.
    (test-cases:check-equal 1 (getf (parametric-model-form model) :version))
    (test-cases:check-equal (getf *legacy-v1-test-form* :parameters)
                            (getf (parametric-model-form model) :parameters))))

(test-cases:deftest one-observation-overfit-and-roundtrip
  ;; Self-contained: earlier versions of this test read the corpus's first
  ;; record from smc-trainer/corpus/pilot-shards/manifest.sexp, a generated
  ;; fixture that is not present in every checkout. A literal input/target
  ;; pair keeps this test able to verify, on its own, that gradient descent
  ;; still drives loss to near zero through the multi-head, multi-layer
  ;; pre-norm architecture -- the highest-risk part of that rewrite.
  (let* ((weights-path (merge-pathnames
                        "smc-trainer/weights/one-observation.sexp"
                        *parametric-tests-root*))
         (input '(0.4d0 -0.2d0 0.1d0 0.6d0 -0.5d0))
         (target '(0.3d0 -0.7d0))
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
