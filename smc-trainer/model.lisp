;;;; A tiny, fully trainable feature-token Transformer in portable Common Lisp.

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
  (loop repeat length collect (trainer-parameter scale)))

(defun trainer-matrix (rows columns &optional (scale 0.08d0))
  (loop repeat rows collect (trainer-vector columns scale)))

(defun trainer-zero-vector (length)
  (loop repeat length collect (trainer-parameter 0.0d0)))

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
  (ad-sum (mapcar #'ad* left right)))

(defun ad-matvec (matrix vector &optional bias)
  (loop for row in matrix for index from 0
        collect (if bias
                    (ad+ (ad-dot row vector) (nth index bias))
                    (ad-dot row vector))))

(defun ad-vector+ (left right) (mapcar #'ad+ left right))

(defun ad-rms-normalize (vector)
  (let* ((squares (mapcar (lambda (x) (ad* x x)) vector))
         (denominator (ad-sqrt (ad+ (ad-mean squares)
                                    (trainer-constant *trainer-epsilon*)))))
    (mapcar (lambda (x) (ad/ x denominator)) vector)))

(defun ad-softmax (scores)
  ;; Subtracting a detached maximum is numerically stable and leaves the exact
  ;; softmax derivative unchanged because softmax is translation invariant.
  (let* ((maximum (reduce #'max scores :key #'ad-value))
         (exponentials
           (mapcar (lambda (score)
                     (ad-exp (ad- score (trainer-constant maximum))))
                   scores))
         (total (ad-sum exponentials)))
    (mapcar (lambda (value) (ad/ value total)) exponentials)))

(defun parametric-forward (model input)
  (unless (= (length input) (parametric-model-feature-count model))
    (error "Expected ~D input features, received ~D."
           (parametric-model-feature-count model) (length input)))
  (let* ((d (parametric-model-d-model model))
         (tokens
           (loop for value in input for identity in (parametric-model-feature-embeddings model)
                 collect
                 (loop for base in identity
                       for weight in (parametric-model-scalar-weights model)
                       for bias in (parametric-model-scalar-bias model)
                       collect (ad+ base (ad+ (ad* weight (trainer-constant value)) bias)))))
         (queries (mapcar (lambda (x) (ad-matvec (parametric-model-wq model) x)) tokens))
         (keys (mapcar (lambda (x) (ad-matvec (parametric-model-wk model) x)) tokens))
         (values (mapcar (lambda (x) (ad-matvec (parametric-model-wv model) x)) tokens))
         (scale (trainer-constant (sqrt (coerce d 'double-float))))
         (attended
           (loop for query in queries collect
             (let* ((scores (mapcar (lambda (key) (ad/ (ad-dot query key) scale)) keys))
                    (probabilities (ad-softmax scores))
                    (mixed
                      (loop for component below d collect
                        (ad-sum
                         (loop for probability in probabilities for value in values
                               collect (ad* probability (nth component value)))))))
               (ad-matvec (parametric-model-wo model) mixed))))
         (after-attention
           (mapcar (lambda (token attention)
                     (ad-rms-normalize (ad-vector+ token attention)))
                   tokens attended))
         (encoded
           (mapcar
            (lambda (state)
              (let* ((hidden (mapcar #'ad-tanh
                                     (ad-matvec (parametric-model-w1 model) state
                                                (parametric-model-b1 model))))
                     (feed-forward
                       (ad-matvec (parametric-model-w2 model) hidden
                                  (parametric-model-b2 model))))
                (ad-rms-normalize (ad-vector+ state feed-forward))))
            after-attention))
         (pooled
           (loop for component below d collect
             (ad-mean (mapcar (lambda (state) (nth component state)) encoded)))))
    (ad-matvec (parametric-model-output-weights model) pooled
               (parametric-model-output-bias model))))

(defun parametric-coordinate-loss (prediction target)
  (ad-mean
   (mapcar (lambda (predicted expected)
             (let ((difference (ad- predicted (trainer-constant expected))))
               (ad* difference difference)))
           prediction target)))

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
  (mapcar #'ad-value (parametric-forward model input)))

(defun trainer-values (tree)
  (if (and (listp tree) (or (null tree) (listp (first tree))))
      (mapcar #'trainer-values tree)
      (mapcar #'ad-value tree)))

(defun parametric-model-form (model)
  (let ((groups (parametric-model-parameter-groups model)))
    (list :format :parametric-feature-transformer :version 1
          :training :full-backpropagation :seed *trainer-seed*
          :feature-count (parametric-model-feature-count model)
          :d-model (parametric-model-d-model model) :d-ff (parametric-model-d-ff model)
          :parameters (mapcar #'trainer-values groups))))

(defun trainer-nodes-from-values (tree)
  (if (and (listp tree) (or (null tree) (listp (first tree))))
      (mapcar #'trainer-nodes-from-values tree)
      (mapcar (lambda (value) (make-ad-node (coerce value 'double-float)
                                            :parameter-p t)) tree)))

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
