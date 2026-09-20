;;;; database.lisp -- predicates, clauses, assert/retract, dynamic-predicate execution.
(in-package :qp)
(engine-policy)

(defstruct (pred (:constructor %make-pred (name arity)))
  name
  (arity 0 :type fixnum)
  (entry #'identity :type function)     ; where a call jumps to (returns the next code)
  (first nil) (last nil)                ; clause chain (doubly linked)
  (nclauses 0 :type fixnum)
  (dynamic nil) (defined nil)
  (library nil)                         ; defined by the built-in library (user code may replace)
  (det nil)                             ; Lisp function returning a boolean (deterministic builtin)
  (lisp nil)                            ; entry written in Lisp
  (compiled nil)
  (index nil)                           ; first-argument hash index (dynamic predicates)
  (nonatomic 0 :type fixnum))           ; number of clauses whose first argument is not atomic

(defstruct (clause (:constructor %make-clause))
  pred head-args body (nvars 0 :type fixnum) (fn nil)
  (prev nil) (next nil) (iprev nil) (inext nil)
  (born 0 :type fixnum) (died most-positive-fixnum :type fixnum)
  (key :var))

(defvar *preds* (make-hash-table :test 'equal))
(defvar *loading-library* nil)

(defun make-stub (p)
  (lambda () (enter-pred p)))

(defun make-pred (name arity)
  (let ((p (%make-pred name arity)))
    (setf (pred-entry p) (make-stub p))
    p))

(defun get-pred (name arity)
  (let ((k (cons name arity)))
    (or (gethash k *preds*) (setf (gethash k *preds*) (make-pred name arity)))))

(defun find-pred (name arity) (gethash (cons name arity) *preds*))

(defun reset-database ()
  (clrhash *preds*)
  (setf $gen 0))

;;; ------------------------------------------------------------------ clauses
(defun first-arg-key (args)
  (if (null args) :var
      (let ((a (car args)))
        (cond ((tv-p a) :var)
              ((or (consp a) (tcell-p a)) :list)
              ((tstr-p a) (tstr-functor a))
              ((simple-vector-p a) (svref a 0))
              ((stringp a) :var)
              (t a)))))

(defun atomic-key-p (k) (or (symbolp k) (numberp k)))

(defun invalidate (p)
  (unless (pred-dynamic p)
    (setf (pred-compiled p) nil)
    (setf (pred-entry p) (make-stub p))))

(defun link-clause (p c where)
  (if (eq where :start)
      (progn (setf (clause-next c) (pred-first p) (clause-prev c) nil)
             (when (pred-first p) (setf (clause-prev (pred-first p)) c))
             (setf (pred-first p) c)
             (unless (pred-last p) (setf (pred-last p) c)))
      (progn (setf (clause-prev c) (pred-last p) (clause-next c) nil)
             (if (pred-last p) (setf (clause-next (pred-last p)) c) (setf (pred-first p) c))
             (setf (pred-last p) c)))
  (incf (pred-nclauses p))
  (unless (atomic-key-p (clause-key c)) (incf (pred-nonatomic p)))
  (when (pred-index p) (index-add p c where)))

(defun add-clause-tpl (p head-args body nvars &key (where :end))
  (when (and (pred-library p) (not *loading-library*))   ; a user definition replaces a library one
    (wipe-pred p) (setf (pred-library p) nil))
  (when (or (pred-det p) (pred-lisp p))
    (setf (pred-det p) nil (pred-lisp p) nil))
  (let ((c (%make-clause :pred p :head-args head-args :body body :nvars nvars
                         :key (first-arg-key head-args))))
    (setf (pred-defined p) t)
    (when *loading-library* (setf (pred-library p) t))
    (when (pred-dynamic p)
      (setf (clause-born c) (incf $gen)))
    (invalidate p)
    (link-clause p c where)
    c))

(defun wipe-pred (p)
  (setf (pred-first p) nil (pred-last p) nil (pred-nclauses p) 0 (pred-index p) nil
        (pred-nonatomic p) 0 (pred-compiled p) nil)
  (setf (pred-entry p) (make-stub p)))

(defun add-clause (head body &key (where :end))
  "HEAD and BODY (list of goals) in surface syntax."
  (let* ((*vt* (make-hash-table :test 'eq)) (*nv* 0)
         (h (conv head)) (b (mapcar #'conv body)))
    (let* ((name (tpl-functor h)) (args (tpl-args h)))
      (unless (and name (symbolp name)) (error "bad clause head ~S" head))
      (add-clause-tpl (get-pred name (length args)) args b *nv* :where where))))

(defmacro <- (head &rest body)
  `(add-clause ',head ',body))

(defun declare-dynamic (spec)
  "SPEC is (/ name arity) in surface syntax."
  (let ((p (get-pred (second spec) (third spec))))
    (make-dynamic p)))

(defun make-dynamic (p)
  (unless (pred-dynamic p)
    (setf (pred-dynamic p) t (pred-defined p) t)
    (when (or (pred-det p) (pred-lisp p)) (setf (pred-det p) nil (pred-lisp p) nil))
    (let ((g (incf $gen)))
      (do ((c (pred-first p) (clause-next c))) ((null c)) (setf (clause-born c) g)))
    (setf (pred-entry p) (lambda () (dyn-entry p))))
  p)

;;; runtime term -> template (assert)
(defun term->template (term)
  (let ((map (make-hash-table :test 'eq)) (n 0))
    (labels ((tp (x)
               (let ((x (deref x)))
                 (cond ((pv-p x) (or (gethash x map)
                                     (setf (gethash x map) (let ((v (make-tv n))) (incf n) v))))
                       ((consp x)
                        (let ((h (tp (car x))) (tl (tp (cdr x))))
                          (if (or (template-p h) (template-p tl)) (make-tcell h tl) (cons h tl))))
                       ((simple-vector-p x)
                        (let ((args (loop for i from 1 below (length x) collect (tp (svref x i)))))
                          (if (some #'template-p args)
                              (make-tstr (svref x 0) (coerce args 'simple-vector))
                              (coerce (cons (svref x 0) args) 'simple-vector))))
                       (t x)))))
      (values #'tp map (lambda () n)))))

(defun split-clause-term (term)
  "Runtime term H or H:-B -> (values head body-term)."
  (let ((x (deref term)))
    (if (and (simple-vector-p x) (= (length x) 3) (string= (symbol-name (svref x 0)) ":-"))
        (values (deref (svref x 1)) (deref (svref x 2)))
        (values x 'true))))

(defun body-term->goals (body)
  "Conjunction as runtime term -> list of goal terms (`,` and :and flattened)."
  (let ((b (deref body)))
    (cond ((and (simple-vector-p b) (> (length b) 1)
                (or (eq (svref b 0) :and) (and (= (length b) 3) (string= (symbol-name (svref b 0)) ","))))
           (loop for i from 1 below (length b) append (body-term->goals (svref b i))))
          ((eq b 'true) nil)
          ((pv-p b) (list (vector 'call b)))
          (t (list b)))))

(defun assert-term (term where)
  (multiple-value-bind (h b) (split-clause-term term)
    (when (pv-p h) (inst-err))
    (let ((name (cond ((symbolp h) h) ((simple-vector-p h) (svref h 0)) ((consp h) (type-err 'callable h))
                      (t (type-err 'callable h))))
          (arity (cond ((symbolp h) 0) (t (1- (length h))))))
      (multiple-value-bind (tp map nv) (term->template term)
        (declare (ignore map))
        ;; convert head and body with a shared variable map
        (let* ((hh (funcall tp h)) (goals (mapcar tp (body-term->goals b))))
          (let ((p (get-pred name arity)))
            (when (and (pred-defined p) (not (pred-dynamic p)) (not (pred-library p)) (not (pred-det p)))
              nil)
            (when (or (pred-library p) (pred-det p) (pred-lisp p)) (wipe-pred p) (setf (pred-library p) nil (pred-det p) nil (pred-lisp p) nil))
            (make-dynamic p)
            (add-clause-tpl p (tpl-args hh) goals (funcall nv) :where where)))))))

;;; ------------------------------------------------------------------ dynamic predicates
(declaim (inline visible-p))
(defun visible-p (c gen)
  (declare (fixnum gen))
  (and (<= (clause-born c) gen) (< gen (clause-died c))))

(defun key-match (ckey k)
  (cond ((eq ckey :var) t)
        ((eq k :any) t)
        ((eq ckey :list) (eq k :list))
        (t (eql ckey k))))

(defun call-key (a0)
  (let ((k (deref a0)))
    (cond ((pv-p k) :any)
          ((stringp k) :any)
          ((consp k) :list)
          ((simple-vector-p k) (svref k 0))
          (t k))))

(defun next-match (c gen key idxp)
  (declare (fixnum gen))
  (loop
    (when (null c) (return nil))
    (when (and (visible-p c gen) (key-match (clause-key c) key)) (return c))
    (setq c (if idxp (clause-inext c) (clause-next c)))))

(defun run-dyn-clause (c)
  "Run clause C against the argument registers; returns the next code."
  (declare (type clause c))
  (if (clause-body c)
      (or (clause-fn c) (compile-dyn-clause c))
      (let ((frame (make-array (clause-nvars c) :initial-element '%unset)) (a $a) (i 0))
        (declare (fixnum i))
        (dolist (tpl (clause-head-args c) $cp)
          (unless (unify-tpl tpl (svref a i) frame) (return (backtrack)))
          (incf i)))))

(defun scan-start (p key)
  "-> (values first-clause-to-try idxp) for a call with first-argument key KEY."
  (if (and (> (pred-arity p) 0) (atomic-key-p key) (not (eq key :any))
           (>= (pred-nclauses p) 8) (zerop (pred-nonatomic p)))
      (progn
        (unless (pred-index p) (build-index p))
        (let ((bucket (gethash key (pred-index p))))
          (values (and bucket (car bucket)) t)))
      (values (pred-first p) nil)))

(defun dyn-entry (p)
  (declare (type pred p))
  (let* ((gen $gen) (arity (pred-arity p))
         (key (if (> arity 0) (call-key (svref $a 0)) :any)))
    (multiple-value-bind (start idxp) (scan-start p key)
      (let ((c (next-match start gen key idxp)))
        (if (null c)
            (backtrack)
            (let ((c2 (next-match (if idxp (clause-inext c) (clause-next c)) gen key idxp)))
              (when c2
                (push-choice (if idxp #'retry-dyn-idx #'retry-dyn) c2 gen arity))
              (run-dyn-clause c)))))))

(defun retry-dyn-1 (idxp)
  (let* ((b $b) (ls $ls) (c (svref ls (+ b +c-s1+))) (gen (svref ls (+ b +c-s2+)))
         (arity (svref ls (+ b +c-n+)))
         (key (if (> (the fixnum arity) 0) (call-key (svref $a 0)) :any)))
    (declare (fixnum b gen))
    (setf $b0 (the fixnum (svref ls b)))
    (let ((c2 (next-match (if idxp (clause-inext c) (clause-next c)) gen key idxp)))
      (if c2
          (setf (svref ls (+ b +c-s1+)) c2)
          (pop-choice)))
    (run-dyn-clause c)))
(defun retry-dyn () (retry-dyn-1 nil))
(defun retry-dyn-idx () (retry-dyn-1 t))

;;; first-argument hash index: key -> (head . tail) of a chain linked through INEXT
(defun build-index (p)
  (let ((h (make-hash-table :test 'eql)))
    (setf (pred-index p) h)
    (do ((c (pred-first p) (clause-next c))) ((null c))
      (index-add-to h c :end))))

(defun index-add-to (h c where)
  (let* ((k (clause-key c)) (b (gethash k h)))
    (setf (clause-iprev c) nil (clause-inext c) nil)
    (cond ((null b) (setf (gethash k h) (cons c c)))
          ((eq where :start)
           (setf (clause-inext c) (car b) (clause-iprev (car b)) c (car b) c))
          (t (setf (clause-iprev c) (cdr b) (clause-inext (cdr b)) c (cdr b) c)))))

(defun index-add (p c where)
  (if (atomic-key-p (clause-key c))
      (index-add-to (pred-index p) c where)
      (setf (pred-index p) nil)))

(defun index-remove (p c)
  (let* ((h (pred-index p)) (b (and h (gethash (clause-key c) h))))
    (when b
      (let ((pv (clause-iprev c)) (nx (clause-inext c)))
        (if pv (setf (clause-inext pv) nx) (setf (car b) nx))
        (if nx (setf (clause-iprev nx) pv) (setf (cdr b) pv))
        (when (null (car b)) (remhash (clause-key c) h))))))

(defun erase-clause (c)
  (declare (type clause c))
  (when (= (clause-died c) most-positive-fixnum)
    (let ((p (clause-pred c)))
      (setf (clause-died c) (incf $gen))
      (let ((pv (clause-prev c)) (nx (clause-next c)))
        (if pv (setf (clause-next pv) nx) (setf (pred-first p) nx))
        (if nx (setf (clause-prev nx) pv) (setf (pred-last p) pv)))
      (when (pred-index p) (index-remove p c))
      (decf (pred-nclauses p))
      (unless (atomic-key-p (clause-key c)) (decf (pred-nonatomic p)))
      t)))
