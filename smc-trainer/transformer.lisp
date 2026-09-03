;;;; A tiny, fully trainable array-based Transformer in portable Common Lisp.
;;;; Native arrays implement vectors and matrices without BLAS/LAPACK.

(defparameter *trainer-seed* 20260902)
(defparameter *trainer-state* *trainer-seed*)
(defparameter *trainer-d-model* 8)
(defparameter *trainer-d-ff* 12)
(defparameter *trainer-epsilon* 1.0d-6)

(defstruct (ad (:constructor make-ad-node (value &key (parameter-p nil))))
  (value 0.0d0 :type double-float)
  (gradient 0.0d0 :type double-float)
  (parents nil)
  (backward (lambda ()) :type function)
  parameter-p)

(defstruct parametric-model feature-count d-model d-ff
  feature-embeddings scalar-weights scalar-bias
  wq wk wv wo w1 b1 w2 b2 output-weights output-bias)

(defun trainer-random ()
  (setf *trainer-state*
        (mod (+ (* 1103515245 *trainer-state*) 12345) 2147483648))
  (- (* 2.0d0 (/ *trainer-state* 2147483648.0d0)) 1.0d0))

(defun trainer-constant (number)
  (make-ad-node (coerce number 'double-float)))

(defun trainer-parameter (&optional (scale 0.08d0))
  (make-ad-node (* scale (trainer-random)) :parameter-p t))

(defun ad+ (a b)
  (let ((out (make-ad-node (+ (ad-value a) (ad-value b)))))
    (setf (ad-parents out) (list a b)
          (ad-backward out)
          (lambda ()
            (incf (ad-gradient a) (ad-gradient out))
            (incf (ad-gradient b) (ad-gradient out))))
    out))

(defun ad-neg (a)
  (let ((out (make-ad-node (- (ad-value a)))))
    (setf (ad-parents out) (list a)
          (ad-backward out) (lambda () (decf (ad-gradient a) (ad-gradient out))))
    out))

(defun ad- (a b) (ad+ a (ad-neg b)))

(defun ad* (a b)
  (let ((out (make-ad-node (* (ad-value a) (ad-value b)))))
    (setf (ad-parents out) (list a b)
          (ad-backward out)
          (lambda ()
            (incf (ad-gradient a) (* (ad-value b) (ad-gradient out)))
            (incf (ad-gradient b) (* (ad-value a) (ad-gradient out)))))
    out))

(defun ad-inverse (a)
  (let ((out (make-ad-node (/ 1.0d0 (ad-value a)))))
    (setf (ad-parents out) (list a)
          (ad-backward out)
          (lambda ()
            (decf (ad-gradient a)
                  (* (ad-gradient out) (ad-value out) (ad-value out)))))
    out))

(defun ad/ (a b) (ad* a (ad-inverse b)))

(defun ad-exp (a)
  (let ((out (make-ad-node (exp (ad-value a)))))
    (setf (ad-parents out) (list a)
          (ad-backward out)
          (lambda () (incf (ad-gradient a) (* (ad-value out) (ad-gradient out)))))
    out))

(defun ad-tanh (a)
  (let ((out (make-ad-node (tanh (ad-value a)))))
    (setf (ad-parents out) (list a)
          (ad-backward out)
          (lambda ()
            (incf (ad-gradient a)
                  (* (- 1.0d0 (* (ad-value out) (ad-value out)))
                     (ad-gradient out)))))
    out))

(defun ad-sqrt (a)
  (let ((out (make-ad-node (sqrt (ad-value a)))))
    (setf (ad-parents out) (list a)
          (ad-backward out)
          (lambda ()
            (incf (ad-gradient a)
                  (* (/ 0.5d0 (ad-value out)) (ad-gradient out)))))
    out))

(defun ad-sum (nodes)
  (reduce #'ad+ nodes :initial-value (trainer-constant 0.0d0)))

(defun ad-mean (nodes)
  (ad/ (ad-sum nodes) (trainer-constant (length nodes))))

(defun ad-topological-order (root)
  (let ((seen (make-hash-table :test #'eq)) (order nil))
    (labels ((visit (node)
               (unless (gethash node seen)
                 (setf (gethash node seen) t)
                 (mapc #'visit (ad-parents node))
                 (push node order))))
      (visit root))
    (nreverse order)))

(defun ad-backpropagate (loss)
  (let ((order (ad-topological-order loss)))
    (dolist (node order) (setf (ad-gradient node) 0.0d0))
    (setf (ad-gradient loss) 1.0d0)
    (dolist (node (reverse order)) (funcall (ad-backward node)))))

(defun trainer-vector (length &optional (scale 0.08d0))
  "Create a native one-dimensional Common Lisp parameter array."
  (let ((result (make-array length)))
    (dotimes (index length result)
      (setf (aref result index) (trainer-parameter scale)))))

(defun trainer-matrix (rows columns &optional (scale 0.08d0))
  "Create a native array of native row arrays; no BLAS/LAPACK is used."
  (let ((result (make-array rows)))
    (dotimes (row rows result)
      (setf (aref result row) (trainer-vector columns scale)))))

(defun trainer-zero-vector (length)
  (trainer-vector length 0.0d0))

(defun trainer-as-vector (sequence)
  "Return SEQUENCE as a native vector, preserving an existing vector."
  (if (vectorp sequence) sequence (coerce sequence 'vector)))

(defun initialize-parametric-model (feature-count
                                    &key (d-model *trainer-d-model*)
                                      (d-ff *trainer-d-ff*)
                                      (seed *trainer-seed*))
  (setf *trainer-state* seed)
  (make-parametric-model
   :feature-count feature-count :d-model d-model :d-ff d-ff
   :feature-embeddings (trainer-matrix feature-count d-model)
   :scalar-weights (trainer-vector d-model)
   :scalar-bias (trainer-zero-vector d-model)
   :wq (trainer-matrix d-model d-model)
   :wk (trainer-matrix d-model d-model)
   :wv (trainer-matrix d-model d-model)
   :wo (trainer-matrix d-model d-model)
   :w1 (trainer-matrix d-ff d-model)
   :b1 (trainer-zero-vector d-ff)
   :w2 (trainer-matrix d-model d-ff)
   :b2 (trainer-zero-vector d-model)
   :output-weights (trainer-matrix 2 d-model)
   :output-bias (trainer-zero-vector 2)))

(defun ad-dot (left right)
  (let* ((left (trainer-as-vector left))
         (right (trainer-as-vector right))
         (length (length left))
         (products (make-array length)))
    (unless (= length (length right))
      (error "Dot-product dimensions differ: ~D and ~D."
             length (length right)))
    (dotimes (index length (ad-sum products))
      (setf (aref products index)
            (ad* (aref left index) (aref right index))))))

(defun ad-matvec (matrix vector &optional bias)
  (let* ((matrix (trainer-as-vector matrix))
         (vector (trainer-as-vector vector))
         (bias (and bias (trainer-as-vector bias)))
         (result (make-array (length matrix))))
    (dotimes (row-index (length matrix) result)
      (let ((value (ad-dot (aref matrix row-index) vector)))
        (setf (aref result row-index)
              (if bias (ad+ value (aref bias row-index)) value))))))

(defun ad-vector+ (left right)
  (let* ((left (trainer-as-vector left))
         (right (trainer-as-vector right))
         (length (length left))
         (result (make-array length)))
    (unless (= length (length right))
      (error "Vector dimensions differ: ~D and ~D." length (length right)))
    (dotimes (index length result)
      (setf (aref result index)
            (ad+ (aref left index) (aref right index))))))

(defun ad-rms-normalize (vector)
  (let* ((vector (trainer-as-vector vector))
         (squares (map 'vector (lambda (x) (ad* x x)) vector))
         (denominator (ad-sqrt (ad+ (ad-mean squares)
                                    (trainer-constant *trainer-epsilon*)))))
    (map 'vector (lambda (x) (ad/ x denominator)) vector)))

(defun ad-softmax (scores)
  ;; Subtracting a detached maximum is numerically stable and leaves the exact
  ;; softmax derivative unchanged because softmax is translation invariant.
  (let* ((maximum (reduce #'max scores :key #'ad-value))
         (exponentials
           (map 'vector (lambda (score)
                          (ad-exp (ad- score (trainer-constant maximum))))
                scores))
         (total (ad-sum exponentials)))
    (map 'vector (lambda (value) (ad/ value total)) exponentials)))

(defun transformer-feature-tokens (model input)
  "Turn each scalar feature into a D-MODEL-dimensional feature token."
  (let ((input (trainer-as-vector input)))
  (unless (= (length input) (parametric-model-feature-count model))
    (error "Expected ~D input features, received ~D."
           (parametric-model-feature-count model) (length input)))
  (let* ((features (length input))
         (d-model (parametric-model-d-model model))
         (tokens (make-array features)))
    (dotimes (feature features tokens)
      (let ((token (make-array d-model))
            (identity (aref (parametric-model-feature-embeddings model) feature))
            (value (aref input feature)))
        (dotimes (component d-model)
          (setf (aref token component)
                (ad+ (aref identity component)
                     (ad+ (ad* (aref (parametric-model-scalar-weights model)
                                     component)
                               (trainer-constant value))
                          (aref (parametric-model-scalar-bias model)
                                component)))))
        (setf (aref tokens feature) token))))))

(defun transformer-self-attention (model tokens)
  "Apply one-head scaled dot-product self-attention to TOKENS."
  (let* ((d (parametric-model-d-model model))
         (tokens (trainer-as-vector tokens))
         (queries (map 'vector (lambda (x) (ad-matvec (parametric-model-wq model) x)) tokens))
         (keys (map 'vector (lambda (x) (ad-matvec (parametric-model-wk model) x)) tokens))
         (values (map 'vector (lambda (x) (ad-matvec (parametric-model-wv model) x)) tokens))
         (scale (trainer-constant (sqrt (coerce d 'double-float))))
         (result (make-array (length queries))))
    (dotimes (query-index (length queries) result)
      (let* ((query (aref queries query-index))
             (scores (map 'vector
                          (lambda (key) (ad/ (ad-dot query key) scale))
                          keys))
             (probabilities (ad-softmax scores))
             (mixed (make-array d)))
        (dotimes (component d)
          (let ((weighted (make-array (length probabilities))))
            (dotimes (token-index (length probabilities))
              (setf (aref weighted token-index)
                    (ad* (aref probabilities token-index)
                         (aref (aref values token-index) component))))
            (setf (aref mixed component) (ad-sum weighted))))
        (setf (aref result query-index)
              (ad-matvec (parametric-model-wo model) mixed))))))

(defun transformer-feed-forward (model state)
  "Apply the position-wise two-layer feed-forward network to one token."
  (let ((hidden (map 'vector #'ad-tanh
                     (ad-matvec (parametric-model-w1 model) state
                                (parametric-model-b1 model)))))
    (ad-matvec (parametric-model-w2 model) hidden
               (parametric-model-b2 model))))

(defun transformer-block (model tokens)
  "Apply self-attention and feed-forward sublayers with residual RMSNorm."
  (let* ((attention (transformer-self-attention model tokens))
         (after-attention
           (map 'vector (lambda (token attended)
                          (ad-rms-normalize (ad-vector+ token attended)))
                tokens attention)))
    (map 'vector
         (lambda (state)
           (ad-rms-normalize
            (ad-vector+ state (transformer-feed-forward model state))))
         after-attention)))

(defun transformer-mean-pool (encoded d-model)
  "Mean-pool encoded feature tokens into one D-MODEL-dimensional vector."
  (let* ((encoded (trainer-as-vector encoded))
         (pooled (make-array d-model)))
    (dotimes (component d-model pooled)
      (setf (aref pooled component)
            (ad-mean
             (map 'vector (lambda (state) (aref state component)) encoded))))))

(defun transformer-forward (model input)
  "Run the complete feature-token Transformer and return two AD coordinates."
  (let* ((tokens (transformer-feature-tokens model input))
         (encoded (transformer-block model tokens))
         (pooled (transformer-mean-pool encoded
                                        (parametric-model-d-model model))))
    (ad-matvec (parametric-model-output-weights model) pooled
               (parametric-model-output-bias model))))

(defun parametric-forward (model input)
  "Compatibility name for TRANSFORMER-FORWARD used by existing artifacts."
  (transformer-forward model input))

(defun parametric-coordinate-loss (prediction target)
  (let ((prediction (trainer-as-vector prediction))
        (target (trainer-as-vector target)))
    (ad-mean
     (map 'vector (lambda (predicted expected)
                    (let ((difference
                            (ad- predicted (trainer-constant expected))))
                      (ad* difference difference)))
          prediction target))))

(defun parametric-model-parameter-groups (model)
  (list (parametric-model-feature-embeddings model)
        (parametric-model-scalar-weights model) (parametric-model-scalar-bias model)
        (parametric-model-wq model) (parametric-model-wk model)
        (parametric-model-wv model) (parametric-model-wo model)
        (parametric-model-w1 model) (parametric-model-b1 model)
        (parametric-model-w2 model) (parametric-model-b2 model)
        (parametric-model-output-weights model) (parametric-model-output-bias model)))

(defun trainer-flatten (tree)
  (cond ((null tree) nil) ((ad-p tree) (list tree))
        ((arrayp tree)
         (loop for value across tree append (trainer-flatten value)))
        ((listp tree) (mapcan #'trainer-flatten tree))
        (t nil)))

(defun parametric-model-parameters (model)
  (mapcan #'trainer-flatten (parametric-model-parameter-groups model)))

(defun make-adam-state (model)
  (let ((moments (make-hash-table :test #'eq)) (velocities (make-hash-table :test #'eq)))
    (dolist (parameter (parametric-model-parameters model))
      (setf (gethash parameter moments) 0.0d0
            (gethash parameter velocities) 0.0d0))
    (list moments velocities)))

(defun adam-update (model state step &key (learning-rate 0.01d0)
                                       (beta1 0.9d0) (beta2 0.999d0))
  (destructuring-bind (moments velocities) state
    (dolist (parameter (parametric-model-parameters model))
      (let* ((gradient (max -10.0d0 (min 10.0d0 (ad-gradient parameter))))
             (moment (+ (* beta1 (gethash parameter moments)) (* (- 1 beta1) gradient)))
             (velocity (+ (* beta2 (gethash parameter velocities))
                          (* (- 1 beta2) gradient gradient)))
             (corrected-moment (/ moment (- 1 (expt beta1 step))))
             (corrected-velocity (/ velocity (- 1 (expt beta2 step)))))
        (setf (gethash parameter moments) moment
              (gethash parameter velocities) velocity)
        (decf (ad-value parameter)
              (* learning-rate corrected-moment
                 (/ 1.0d0 (+ (sqrt corrected-velocity) 1.0d-8))))))))

(defun train-one-observation (model input target &key (epochs 600) (learning-rate 0.01d0))
  (let ((optimizer (make-adam-state model)) (initial-loss nil) (final-loss nil))
    (loop for epoch from 1 to epochs do
      (let* ((prediction (parametric-forward model input))
             (loss (parametric-coordinate-loss prediction target)))
        (unless initial-loss (setf initial-loss (ad-value loss)))
        (ad-backpropagate loss)
        (adam-update model optimizer epoch :learning-rate learning-rate)
        (setf final-loss (ad-value loss))))
    (values model initial-loss final-loss)))

(defun parametric-predict (model input)
  ;; Keep the public coordinate result list-compatible for existing callers;
  ;; all Transformer tensor computation above uses native arrays.
  (coerce (map 'vector #'ad-value (parametric-forward model input)) 'list))

(defun trainer-values (tree)
  ;; Serialize arrays as lists to retain compatibility with version-1 models.
  (if (and (arrayp tree)
           (or (zerop (length tree)) (arrayp (aref tree 0))))
      (loop for value across tree collect (trainer-values value))
      (loop for value across tree collect (ad-value value))))

(defun parametric-model-form (model)
  (let ((groups (parametric-model-parameter-groups model)))
    (list :format :parametric-feature-transformer :version 1
          :training :full-backpropagation :seed *trainer-seed*
          :feature-count (parametric-model-feature-count model)
          :d-model (parametric-model-d-model model) :d-ff (parametric-model-d-ff model)
          :parameters (mapcar #'trainer-values groups))))

(defun trainer-nodes-from-values (tree)
  ;; Accept the historical nested-list representation and rebuild array tensors.
  (let ((tree (trainer-as-vector tree)))
    (if (and (plusp (length tree))
             (or (listp (aref tree 0)) (arrayp (aref tree 0))))
        (map 'vector #'trainer-nodes-from-values tree)
        (map 'vector
             (lambda (value)
               (make-ad-node (coerce value 'double-float) :parameter-p t))
             tree))))

(defun form-parametric-model (form)
  (unless (and (eq (getf form :format) :parametric-feature-transformer)
               (= (getf form :version) 1))
    (error "Unsupported parametric model format."))
  (let ((groups (mapcar #'trainer-nodes-from-values (getf form :parameters))))
    (apply #'make-parametric-model
           :feature-count (getf form :feature-count)
           :d-model (getf form :d-model) :d-ff (getf form :d-ff)
           (loop for key in '(:feature-embeddings :scalar-weights :scalar-bias
                              :wq :wk :wv :wo :w1 :b1 :w2 :b2
                              :output-weights :output-bias)
                 for value in groups append (list key value)))))

(defun save-parametric-model (model path)
  (ensure-directories-exist path)
  (with-open-file (stream path :direction :output :if-exists :supersede
                               :if-does-not-exist :create)
    (let ((*print-pretty* t) (*print-readably* t))
      (write (parametric-model-form model) :stream stream) (terpri stream))))

(defun load-parametric-model (path)
  (with-open-file (stream path)
    (let ((*read-eval* nil)) (form-parametric-model (read stream)))))
