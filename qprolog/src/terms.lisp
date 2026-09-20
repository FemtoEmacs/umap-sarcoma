;;;; terms.lisp -- surface syntax <-> internal terms, templates, arithmetic, ordering.
(in-package :qp)
(engine-policy)

;;; ------------------------------------------------------------------ templates
;;; A clause is stored as a template: ground subterms are ordinary (shared) terms;
;;; non-ground ones are TV / TCELL / TSTR nodes.
(defstruct (tv (:constructor make-tv (idx))) (idx 0 :type fixnum) (name nil))
(defstruct (tcell (:constructor make-tcell (head tail))) head tail)
(defstruct (tstr (:constructor make-tstr (functor args))) functor (args #() :type simple-vector))

(declaim (inline template-p))
(defun template-p (x) (or (tv-p x) (tcell-p x) (tstr-p x)))

(defun var-sym-p (x)
  (and (symbolp x) x
       (let ((n (symbol-name x)))
         (and (plusp (length n)) (or (char= (char n 0) #\?) (string= n "_"))))))

(defun anon-sym-p (x) (and (symbolp x) x (string= (symbol-name x) "_")))

(defvar *vt*)      ; symbol -> tv for the clause being converted
(defvar *nv*)      ; number of tv made

(defun new-tv (&optional name)
  (let ((v (make-tv *nv*))) (incf *nv*) (setf (tv-name v) name) v))

(defvar *package-qp* (find-package :qprolog))
(defvar *package-kw* (find-package :keyword))

(defun proper-list-p (x)
  (loop (cond ((null x) (return t)) ((consp x) (setq x (cdr x))) (t (return nil)))))

(defun home-sym (x)
  "Atoms are symbols of package QP.  A symbol read in another package (say CL-USER, at the
REPL) is mapped to the QP symbol of the same name; keywords and uninterned symbols stay."
  (let ((p (symbol-package x)))
    (if (or (null p) (eq p *package-qp*) (eq p *package-kw*))
        x
        (values (intern (symbol-name x) *package-qp*)))))

(defun conv (x)
  "Surface syntax -> template (or ground term)."
  (cond ((null x) nil)
        ((symbolp x)
         (let ((x (home-sym x)))
           (cond ((anon-sym-p x) (new-tv "_"))
                 ((var-sym-p x) (or (gethash x *vt*) (setf (gethash x *vt*) (new-tv x))))
                 (t x))))
        ((atom x) x)                                    ; number, string
        ((eq (car x) :l) (conv-marked-list (cdr x)))
        ((not (proper-list-p x)) (conv-list x))
        ((and (symbolp (car x)) (car x) (not (var-sym-p (car x))))
         (let ((f (home-sym (car x))))
           (if (null (cdr x))
               f
               (let ((args (mapcar #'conv (cdr x))))
                 (if (some #'template-p args)
                     (make-tstr f (coerce args 'simple-vector))
                     (coerce (cons f args) 'simple-vector))))))
        (t (conv-list x))))

(defun conv-marked-list (x)
  "(:l e1 .. en) or (:l e1 .. en :tail T): a list whose last cdr is T."
  (let ((elems nil) (tail nil))
    (loop while (consp x)
          do (if (eq (car x) :tail)
                 (progn (setq tail (conv (cadr x))) (setq x nil))
                 (progn (push (conv (car x)) elems) (setq x (cdr x)))))
    (dolist (e elems tail)
      (setq tail (if (or (template-p e) (template-p tail)) (make-tcell e tail) (cons e tail))))))

(defun conv-list (x)
  (let ((elems nil))
    (loop while (consp x) do (push (conv (car x)) elems) (setq x (cdr x)))
    (let ((tail (conv x)))
      (dolist (e elems tail)
        (setq tail (if (or (template-p e) (template-p tail)) (make-tcell e tail) (cons e tail)))))))

(defun convert-clause-term (x)
  "Returns (values template nvars)."
  (let ((*vt* (make-hash-table :test 'eq)) (*nv* 0))
    (let ((tpl (conv x))) (values tpl *nv*))))

;;; template accessors for goals / heads
(defun tpl-functor (x)
  (cond ((symbolp x) x) ((simple-vector-p x) (svref x 0)) ((tstr-p x) (tstr-functor x)) (t nil)))
(defun tpl-args (x)
  "Argument templates as a list."
  (cond ((symbolp x) nil)
        ((simple-vector-p x) (cdr (coerce x 'list)))
        ((tstr-p x) (coerce (tstr-args x) 'list))
        ((or (consp x) (tcell-p x)) (list (if (consp x) (car x) (tcell-head x))
                                          (if (consp x) (cdr x) (tcell-tail x))))
        (t nil)))
(defun tpl-arity (x) (length (tpl-args x)))

;;; ------------------------------------------------------------------ instantiation
(defconstant +unset+ '%unset)

(defun instantiate (tpl frame)
  (declare (simple-vector frame))
  (cond ((tv-p tpl)
         (let ((cur (svref frame (tv-idx tpl))))
           (if (eq cur '%unset) (setf (svref frame (tv-idx tpl)) (new-var)) cur)))
        ((tcell-p tpl) (cons (instantiate (tcell-head tpl) frame) (instantiate (tcell-tail tpl) frame)))
        ((tstr-p tpl)
         (let* ((args (tstr-args tpl)) (n (length args)) (v (make-array (1+ n))))
           (setf (svref v 0) (tstr-functor tpl))
           (dotimes (i n) (setf (svref v (1+ i)) (instantiate (svref args i) frame)))
           v))
        (t tpl)))

(defun unify-tpl (tpl term frame)
  "Unify template TPL (renamed through FRAME) with runtime TERM."
  (declare (simple-vector frame))
  (cond ((tv-p tpl)
         (let ((cur (svref frame (tv-idx tpl))))
           (if (eq cur '%unset)
               (progn (setf (svref frame (tv-idx tpl)) term) t)
               (unify cur term))))
        ((tcell-p tpl)
         (let ((v (deref term)))
           (cond ((consp v) (and (unify-tpl (tcell-head tpl) (car v) frame)
                                 (unify-tpl (tcell-tail tpl) (cdr v) frame)))
                 ((pv-p v) (bind v (instantiate tpl frame)))
                 (t nil))))
        ((tstr-p tpl)
         (let ((v (deref term)) (args (tstr-args tpl)))
           (cond ((simple-vector-p v)
                  (and (= (length v) (1+ (length args)))
                       (eq (svref v 0) (tstr-functor tpl))
                       (dotimes (i (length args) t)
                         (unless (unify-tpl (svref args i) (svref v (1+ i)) frame) (return nil)))))
                 ((pv-p v) (bind v (instantiate tpl frame)))
                 (t nil))))
        (t (unify tpl term))))

;;; ------------------------------------------------------------------ term utilities
(defun list->term (items &optional (tail nil))
  (let ((r tail)) (dolist (i (reverse items) r) (setq r (cons i r)))))

(defun term-list (term)
  "Prolog list -> Lisp list of elements, or :partial / :improper."
  (let ((out nil) (x (deref term)))
    (loop (cond ((null x) (return (nreverse out)))
                ((consp x) (push (car x) out) (setq x (deref (cdr x))))
                ((pv-p x) (return :partial))
                (t (return :improper))))))

(defun term->lisp (term &optional (names (make-hash-table :test 'eq)))
  "Runtime term -> readable Lisp data (variables as ?_G<n>; lists (a b), compounds (f a b))."
  (let ((x (deref term)))
    (cond ((pv-p x) (or (gethash x names)
                        (setf (gethash x names)
                              (make-symbol (format nil "?_G~D" (hash-table-count names))))))
          ((consp x)
           (let ((items nil))
             (loop (push (term->lisp (car x) names) items)
                   (setq x (deref (cdr x)))
                   (unless (consp x) (return)))
             (let ((tail (if (null x) nil (term->lisp x names))))
               (let ((l (nreverse items)))
                 (cond ((simple-vector-p x) (list* :l (append l (list :tail tail))))
                       ((and (null tail) (symbolp (car l)) (car l) (symbol-package (car l))) (cons :l l))
                       (t (append l tail)))))))
          ((simple-vector-p x)
           (cons (svref x 0) (loop for i from 1 below (length x) collect (term->lisp (svref x i) names))))
          (t x))))

(defun copy-term (term)
  (let ((map (make-hash-table :test 'eq)))
    (labels ((cp (x)
               (let ((x (deref x)))
                 (cond ((pv-p x) (or (gethash x map) (setf (gethash x map) (new-var))))
                       ((consp x) (cons (cp (car x)) (cp (cdr x))))
                       ((simple-vector-p x)
                        (let ((v (make-array (length x))))
                          (setf (svref v 0) (svref x 0))
                          (loop for i from 1 below (length x) do (setf (svref v i) (cp (svref x i))))
                          v))
                       (t x)))))
      (cp term))))

(defun ground-term-p (term)
  (let ((x (deref term)))
    (cond ((pv-p x) nil)
          ((consp x) (and (ground-term-p (car x)) (ground-term-p (cdr x))))
          ((simple-vector-p x) (loop for i from 1 below (length x) always (ground-term-p (svref x i))))
          (t t))))

(defun term-vars (term)
  (let ((seen nil) (out nil))
    (labels ((walk (x)
               (let ((x (deref x)))
                 (cond ((pv-p x) (unless (member x seen :test #'eq) (push x seen) (push x out)))
                       ((consp x) (walk (car x)) (walk (cdr x)))
                       ((simple-vector-p x) (loop for i from 1 below (length x) do (walk (svref x i))))))))
      (walk term))
    (nreverse out)))

;;; ------------------------------------------------------------------ errors
(defun throw-error (formal &optional (context nil))
  (error 'prolog-error :term (vector 'error formal (or context (new-var)))))

(defun type-err (type culprit) (throw-error (vector 'type_error type culprit)))
(defun inst-err () (throw-error 'instantiation_error))

;;; ------------------------------------------------------------------ arithmetic
(defun ar-eval (x)
  "Evaluate an arithmetic expression given as a runtime term."
  (let ((x (deref x)))
    (cond ((numberp x) x)
          ((pv-p x) (inst-err))
          ((symbolp x)
           (let ((n (symbol-name x)))
             (cond ((string-equal n "pi") pi)
                   ((string-equal n "e") (exp 1d0))
                   ((string-equal n "inf") sb-ext:double-float-positive-infinity)
                   ((string-equal n "nan") (- sb-ext:double-float-positive-infinity sb-ext:double-float-positive-infinity))
                   ((string-equal n "max_tagged_integer") (1- (ash 1 60)))
                   ((string-equal n "random") (random 1d0))
                   ((string-equal n "cputime") (/ (get-internal-run-time) (float internal-time-units-per-second 1d0)))
                   (t (type-err 'evaluable x)))))
          ((simple-vector-p x)
           (let ((f (symbol-name (svref x 0))) (n (1- (length x))))
             (case n
               (1 (ar-apply1 f (ar-eval (svref x 1)) x))
               (2 (ar-apply2 f (ar-eval (svref x 1)) (ar-eval (svref x 2)) x))
               (t (type-err 'evaluable x)))))
          ((and (consp x) (null (deref (cdr x)))) (ar-eval (car x)))     ; "a" style
          (t (type-err 'evaluable x)))))

(declaim (inline ar-val))
(defun ar-val (x)
  (let ((v (deref x))) (if (numberp v) v (ar-eval v))))

(defun ar-int (x) (if (integerp x) x (type-err 'integer x)))

(defun ar-div (x y)
  (cond ((and (integerp x) (integerp y))
         (when (zerop y) (throw-error (vector 'evaluation_error 'zero_divisor)))
         (multiple-value-bind (q r) (truncate x y) (if (zerop r) q (/ (float x 1d0) (float y 1d0)))))
        (t (when (and (zerop y) (integerp y)) (throw-error (vector 'evaluation_error 'zero_divisor)))
           (/ (float x 1d0) (float y 1d0)))))

(defun ar-intdiv (x y)
  (ar-int x) (ar-int y)
  (when (zerop y) (throw-error (vector 'evaluation_error 'zero_divisor)))
  (values (truncate x y)))

(defun ar-mod (x y)
  (ar-int x) (ar-int y)
  (when (zerop y) (throw-error (vector 'evaluation_error 'zero_divisor)))
  (mod x y))

(defun ar-rem (x y)
  (ar-int x) (ar-int y)
  (when (zerop y) (throw-error (vector 'evaluation_error 'zero_divisor)))
  (rem x y))

(defun ar-floor-div (x y)
  (ar-int x) (ar-int y)
  (when (zerop y) (throw-error (vector 'evaluation_error 'zero_divisor)))
  (values (floor x y)))

(defun ar-pow (x y)
  (cond ((and (integerp x) (integerp y))
         (if (>= y 0) (expt x y)
             (cond ((eql x 1) 1) ((eql x -1) (if (evenp y) 1 -1))
                   (t (type-err 'float x)))))
        (t (let ((r (expt (float x 1d0) (float y 1d0)))) (if (complexp r) (throw-error (vector 'evaluation_error 'undefined)) r)))))

(defun ar-apply2 (f x y term)
  (cond ((string= f "+") (+ x y)) ((string= f "-") (- x y)) ((string= f "*") (* x y))
        ((string= f "/") (ar-div x y))
        ((string= f "//") (ar-intdiv x y))
        ((string-equal f "mod") (ar-mod x y)) ((string-equal f "rem") (ar-rem x y))
        ((string-equal f "div") (ar-floor-div x y))
        ((string-equal f "min") (if (< y x) y x)) ((string-equal f "max") (if (> y x) y x))
        ((string= f ">>") (ash (ar-int x) (- (ar-int y)))) ((string= f "<<") (ash (ar-int x) (ar-int y)))
        ((string= f "/\\") (logand (ar-int x) (ar-int y))) ((string= f "\\/") (logior (ar-int x) (ar-int y)))
        ((string-equal f "xor") (logxor (ar-int x) (ar-int y)))
        ((string= f "**") (if (and (integerp x) (integerp y)) (ar-pow x y) (ar-pow (float x 1d0) y)))
        ((string= f "^") (ar-pow x y))
        ((string-equal f "gcd") (gcd (ar-int x) (ar-int y)))
        ((string-equal f "atan2") (atan (float x 1d0) (float y 1d0)))
        ((string-equal f "atan") (atan (float x 1d0) (float y 1d0)))
        ((string-equal f "copysign") (float-sign (float y 1d0) (abs (float x 1d0))))
        ((string-equal f "truncate") (type-err 'evaluable term))
        (t (type-err 'evaluable term))))

(defun ar-apply1 (f x term)
  (cond ((string= f "-") (- x)) ((string= f "+") x)
        ((string-equal f "abs") (abs x))
        ((string-equal f "sign") (if (integerp x) (signum x) (float-sign x (if (zerop x) 0d0 1d0))))
        ((string-equal f "min") x) ((string-equal f "max") x)
        ((string= f "\\") (lognot (ar-int x)))
        ((string-equal f "sqrt") (if (< x 0) (throw-error (vector 'evaluation_error 'undefined)) (sqrt (float x 1d0))))
        ((string-equal f "sin") (sin (float x 1d0))) ((string-equal f "cos") (cos (float x 1d0)))
        ((string-equal f "tan") (tan (float x 1d0))) ((string-equal f "atan") (atan (float x 1d0)))
        ((string-equal f "exp") (exp (float x 1d0)))
        ((string-equal f "log") (if (<= x 0) (throw-error (vector 'evaluation_error 'undefined)) (log (float x 1d0))))
        ((string-equal f "float") (float x 1d0))
        ((string-equal f "integer") (if (integerp x) x (values (round x))))
        ((string-equal f "truncate") (if (integerp x) x (values (truncate x))))
        ((string-equal f "round") (if (integerp x) x (values (round-half-up x))))
        ((string-equal f "ceiling") (if (integerp x) x (values (ceiling x))))
        ((string-equal f "floor") (if (integerp x) x (values (floor x))))
        ((string-equal f "float_integer_part") (float (truncate x) 1d0))
        ((string-equal f "float_fractional_part") (- x (truncate x)))
        ((string-equal f "succ") (1+ x))
        ((string-equal f "random") (random (ar-int x)))
        ((string-equal f "msb") (1- (integer-length (ar-int x))))
        (t (type-err 'evaluable term))))

(defun round-half-up (x) (if (>= x 0) (floor (+ x 1/2)) (ceiling (- x 1/2))))

(declaim (inline ar+ ar- ar* ar<  ar> ar<= ar>= ar= ar/=))
(defun ar+ (x y) (if (and (typep x 'fixnum) (typep y 'fixnum)) (+ (the fixnum x) (the fixnum y)) (+ (the number x) (the number y))))
(defun ar- (x y) (if (and (typep x 'fixnum) (typep y 'fixnum)) (- (the fixnum x) (the fixnum y)) (- (the number x) (the number y))))
(defun ar* (x y) (if (and (typep x 'fixnum) (typep y 'fixnum)) (* (the fixnum x) (the fixnum y)) (* (the number x) (the number y))))
(defun ar< (x y) (if (and (typep x 'fixnum) (typep y 'fixnum)) (< (the fixnum x) (the fixnum y)) (< (the real x) (the real y))))
(defun ar> (x y) (if (and (typep x 'fixnum) (typep y 'fixnum)) (> (the fixnum x) (the fixnum y)) (> (the real x) (the real y))))
(defun ar<= (x y) (if (and (typep x 'fixnum) (typep y 'fixnum)) (<= (the fixnum x) (the fixnum y)) (<= (the real x) (the real y))))
(defun ar>= (x y) (if (and (typep x 'fixnum) (typep y 'fixnum)) (>= (the fixnum x) (the fixnum y)) (>= (the real x) (the real y))))
(defun ar= (x y) (if (and (typep x 'fixnum) (typep y 'fixnum)) (= (the fixnum x) (the fixnum y)) (= (the real x) (the real y))))
(defun ar/= (x y) (not (ar= x y)))

;;; ------------------------------------------------------------------ standard order
(defun atom-name (a) (symbol-name a))

(defun compare-names (x y)
  "Compare two atom names in the standard order.  The reader folds atoms to upper case, so
letters are compared case-insensitively (as if the source had been written in lower case);
names equal up to case are then ordered by their exact characters."
  (declare (simple-string x y))
  (let ((lx (length x)) (ly (length y)))
    (dotimes (i (min lx ly))
      (let ((a (char-downcase (schar x i))) (b (char-downcase (schar y i))))
        (cond ((char< a b) (return-from compare-names -1))
              ((char> a b) (return-from compare-names 1)))))
    (cond ((< lx ly) -1) ((> lx ly) 1)
          ((string< x y) -1) ((string> x y) 1) (t 0))))

(defun type-rank (x)
  (cond ((pv-p x) 0) ((numberp x) 1) ((symbolp x) 3) ((stringp x) 2) (t 5)))

(defun compare-terms (a b)
  "-1, 0 or 1 in the standard order of terms."
  (let ((a (deref a)) (b (deref b)))
    (cond ((eq a b) 0)
          (t (let ((ra (type-rank a)) (rb (type-rank b)))
               (cond ((/= ra rb) (if (< ra rb) -1 1))
                     (t (case ra
                          (0 (let ((x (pv-serial a)) (y (pv-serial b))) (cond ((< x y) -1) ((> x y) 1) (t 0))))
                          (1 (cond ((< a b) -1) ((> a b) 1)
                                   ((and (floatp a) (integerp b)) -1)
                                   ((and (integerp a) (floatp b)) 1)
                                   (t 0)))
                          (3 (compare-names (atom-name a) (atom-name b)))
                          (2 (cond ((string< a b) -1) ((string> a b) 1) (t 0)))
                          (t (compare-compound a b))))))))))

(defun cmp-arity (x) (if (consp x) 2 (1- (length x))))
(defun cmp-name (x) (if (consp x) (intern "[|]" :qp) (svref x 0)))
(defun cmp-arg (x i) (if (consp x) (if (= i 1) (car x) (cdr x)) (svref x i)))

(defun compare-compound (a b)
  (let ((na (cmp-arity a)) (nb (cmp-arity b)))
    (cond ((< na nb) -1) ((> na nb) 1)
          (t (let ((fa (cmp-name a)) (fb (cmp-name b)))
               (cond ((not (eq fa fb)) (compare-names (atom-name fa) (atom-name fb)))
                     (t (loop for i from 1 to na
                              do (let ((c (compare-terms (cmp-arg a i) (cmp-arg b i))))
                                   (unless (zerop c) (return-from compare-compound c))))
                        0)))))))
