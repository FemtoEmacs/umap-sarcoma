;;;; machine.lisp -- terms, registers, stacks, trail, unification, backtracking.
;;;;
;;;; Term representation (all Lisp objects, so SBCL's collector manages them):
;;;;   atom          symbol           ([] is NIL)
;;;;   number        integer / double-float
;;;;   list cell     cons             (head . tail)          -- distinct from compounds
;;;;   compound f/n  simple-vector    #(f a1 ... an)         -- functor at index 0
;;;;   variable      PV struct        (val serial)
;;;; Control state lives in preallocated simple-vectors: the local stack $LS
;;;; (environment frames and choice-point frames, addressed by fixnum index),
;;;; the argument registers $A and the trail $TRAIL.  No conses or structs are
;;;; allocated for control.

(in-package :qp)

(defmacro engine-policy ()
  (if (member :qp-debug *features*)
      '(declaim (optimize (speed 1) (safety 3) (debug 2)))
      '(declaim (optimize (speed 3) (safety 0) (debug 0)))))
(engine-policy)

(defparameter *clause-policy*
  (if (member :qp-debug *features*)
      '(optimize (speed 1) (safety 3) (debug 2))
      '(optimize (speed 3) (safety 0) (debug 0) (compilation-speed 0))))

(define-condition prolog-error (error)
  ((term :initarg :term :reader prolog-error-term))
  (:report (lambda (c s) (format s "Prolog error: ~S" (term->lisp (prolog-error-term c))))))

;;; ------------------------------------------------------------------ registers
(defmacro defg (name init type)
  `(progn (sb-ext:defglobal ,name ,init) (declaim (type ,type ,name))))

(defconstant +max-arity+ 255)
(defg $a (make-array 256 :initial-element 0) simple-vector)           ; argument registers
(defg $ls (make-array 65536 :initial-element 0) simple-vector)        ; local stack
(defg $trail (make-array 16384 :initial-element 0) simple-vector)
(defg $e 0 fixnum)          ; current environment frame (index into $ls)
(defg $b 0 fixnum)          ; newest choice frame
(defg $b0 0 fixnum)         ; B at predicate entry: the cut barrier
(defg $cp #'identity function)   ; continuation code
(defg $tr 0 fixnum)         ; trail top
(defg $hb 0 fixnum)         ; var serial at newest choice point: older vars are trailed
(defg $vc 0 fixnum)         ; var serial counter
(defg $gen 0 fixnum)        ; database generation

;;; environment frame: [prevE cp cutB size y0 y1 ...]
(defconstant +e-prev+ 0) (defconstant +e-cp+ 1) (defconstant +e-cutb+ 2)
(defconstant +e-size+ 3) (defconstant +e-y+ 4)
;;; choice frame: [prevB alt E cp tr vc s1 s2 nargs args...]
(defconstant +c-prev+ 0) (defconstant +c-alt+ 1) (defconstant +c-e+ 2) (defconstant +c-cp+ 3)
(defconstant +c-tr+ 4) (defconstant +c-vc+ 5) (defconstant +c-s1+ 6) (defconstant +c-s2+ 7)
(defconstant +c-n+ 8) (defconstant +c-args+ 9)

(defmacro ls (i) `(svref $ls ,i))

;;; ------------------------------------------------------------------ variables
(defstruct (pv (:constructor %make-pv (serial)) (:copier nil) (:predicate pv-p))
  (val '%unb)
  (serial 0 :type fixnum))

(declaim (inline new-var deref bind))
(defun new-var ()
  (%make-pv (setq $vc (the fixnum (1+ $vc)))))

(defun deref (x)
  (loop
    (if (pv-p x)
        (let ((v (pv-val x)))
          (if (eq v '%unb) (return x) (setq x v)))
        (return x))))

(defun trail-grow ()
  (let ((new (make-array (* 2 (length $trail)) :initial-element 0)))
    (replace new $trail)
    (setf $trail new)))

(defun trail-push (v)
  (let ((tr $tr))
    (when (>= tr (length $trail)) (trail-grow))
    (setf (svref $trail tr) v)
    (setf $tr (the fixnum (1+ tr)))))

(defun bind (v val)
  (declare (type pv v))
  (setf (pv-val v) val)
  (when (<= (pv-serial v) $hb) (trail-push v))
  t)

(defun undo-trail (mark)
  (declare (fixnum mark))
  (let ((tr $tr) (trail $trail))
    (declare (fixnum tr))
    (loop while (> tr mark)
          do (decf tr)
             (let ((v (svref trail tr)))
               (setf (pv-val (the pv v)) '%unb)
               (setf (svref trail tr) 0)))
    (setf $tr tr)))

;;; ------------------------------------------------------------------ unification
(defun unify (a b)
  (let ((a (deref a)) (b (deref b)))
    (cond ((eq a b) t)
          ((pv-p a)
           (if (and (pv-p b) (< (pv-serial a) (pv-serial b)))
               (bind b a)
               (bind a b)))
          ((pv-p b) (bind b a))
          ((consp a)
           (and (consp b)
                (unify (car a) (car b))
                (unify (cdr a) (cdr b))))
          ((simple-vector-p a)
           (and (simple-vector-p b)
                (let ((n (length a)))
                  (and (= n (length b))
                       (eq (svref a 0) (svref b 0))
                       (progn
                         (loop for i fixnum from 1 below (1- n)
                               do (unless (unify (svref a i) (svref b i)) (return-from unify nil)))
                         (unify (svref a (1- n)) (svref b (1- n))))))))
          ((numberp a) (and (numberp b) (eql a b)))
          ((stringp a) (and (stringp b) (string= a b)))
          (t nil))))

;;; ------------------------------------------------------------------ stack frames
(defun grow-ls (needed)
  (declare (fixnum needed))
  (let ((new (make-array (max (* 2 (length $ls)) (+ needed 65536)) :initial-element 0)))
    (replace new $ls)
    (setf $ls new)))

(declaim (inline frame-top))
(defun frame-top ()
  (let ((e $e) (b $b))
    (declare (fixnum e b))
    (max (the fixnum (+ e (the fixnum (ls (+ e +e-size+)))))
         (the fixnum (+ b +c-args+ (the fixnum (ls (+ b +c-n+))))))))

(defun alloc-env (nv)
  (declare (fixnum nv))
  (let* ((top (frame-top)) (size (+ +e-y+ nv)))
    (declare (fixnum top size))
    (when (> (+ top size 300) (length $ls)) (grow-ls (+ top size 300)))
    (let ((ls $ls))
      (setf (svref ls top) $e
            (svref ls (+ top +e-cp+)) $cp
            (svref ls (+ top +e-cutb+)) $b0
            (svref ls (+ top +e-size+)) size)
      (setf $e top)
      top)))

(defun push-choice (alt s1 s2 n)
  (declare (fixnum n) (function alt))
  (let* ((top (frame-top)) (size (+ +c-args+ n)))
    (declare (fixnum top size))
    (when (> (+ top size 300) (length $ls)) (grow-ls (+ top size 300)))
    (let ((ls $ls) (a $a))
      (setf (svref ls top) $b
            (svref ls (+ top +c-alt+)) alt
            (svref ls (+ top +c-e+)) $e
            (svref ls (+ top +c-cp+)) $cp
            (svref ls (+ top +c-tr+)) $tr
            (svref ls (+ top +c-vc+)) $vc
            (svref ls (+ top +c-s1+)) s1
            (svref ls (+ top +c-s2+)) s2
            (svref ls (+ top +c-n+)) n)
      (dotimes (i n) (setf (svref ls (+ top +c-args+ i)) (svref a i)))
      (setf $b top $hb $vc)
      top)))

(declaim (inline cut-to pop-choice))
(defun cut-to (b)
  (declare (fixnum b))
  (setf $b b $hb (the fixnum (ls (+ b +c-vc+)))))

(defun pop-choice ()
  (let ((pb (ls $b)))
    (declare (fixnum pb))
    (setf $b pb $hb (the fixnum (ls (+ pb +c-vc+))))))

;;; backtrack: restore the newest choice frame and run its alternative
(defun backtrack ()
  (let ((b $b) (ls $ls))
    (declare (fixnum b))
    (undo-trail (svref ls (+ b +c-tr+)))
    (setf $e (svref ls (+ b +c-e+))
          $cp (svref ls (+ b +c-cp+))
          $hb (svref ls (+ b +c-vc+)))
    (let ((n (svref ls (+ b +c-n+))) (a $a))
      (declare (fixnum n))
      (dotimes (i n) (setf (svref a i) (svref ls (+ b +c-args+ i)))))
    (funcall (the function (svref ls (+ b +c-alt+))))))

;;; several candidate clauses (a simple-vector of clause functions)
(defun retry-cands ()
  (let* ((b $b) (ls $ls) (cands (svref ls (+ b +c-s1+))) (i (svref ls (+ b +c-s2+))))
    (declare (fixnum b i) (simple-vector cands))
    (setf $b0 (the fixnum (svref ls b)))
    (if (= i (1- (length cands)))
        (pop-choice)
        (setf (svref ls (+ b +c-s2+)) (1+ i)))
    (svref cands i)))

(defun call-cands (cands n)
  (declare (simple-vector cands) (fixnum n))
  (push-choice #'retry-cands cands 1 n)
  (svref cands 0))

;;; a generic nondeterministic builtin: S1 is a closure returning :fail, :last or T
(defun retry-iter ()
  (let* ((b $b) (ls $ls) (fn (svref ls (+ b +c-s1+))))
    (declare (function fn) (fixnum b))
    (let ((r (funcall fn)))
      (case r
        ((nil :fail) (pop-choice) (backtrack))
        (:last (pop-choice) $cp)
        (t $cp)))))

(defun call-iter (fn)
  "Run FN (returns :fail, :last or true) as a nondeterministic builtin."
  (declare (function fn) (ignorable fn))
  (push-choice #'retry-iter fn 0 0)
  (retry-iter))

;;; ------------------------------------------------------------------ running
(defun stop-success () (throw '%stop t))
(defun stop-fail () (throw '%stop nil))

(defun run (fn)
  "The trampoline.  A Prolog error (condition PROLOG-ERROR) is offered to the catch/3 frames
of this run (see HANDLE-THROW); if none takes it, it propagates to an enclosing run."
  (declare (function fn))
  (catch '%stop
    (loop
      (handler-case (loop (setq fn (funcall fn)))
        (prolog-error (c) (setq fn (handle-throw c)))))))

(defun init-machine ()
  "Empty stacks: an environment frame at 0 and a base choice frame at 4."
  (let ((ls $ls))
    (setf (svref ls 0) 0 (svref ls 1) #'stop-success (svref ls 2) 4 (svref ls 3) 4)
    (setf (svref ls 4) 4 (svref ls 5) #'stop-fail (svref ls 6) 0 (svref ls 7) #'stop-success
          (svref ls 8) 0 (svref ls 9) 0 (svref ls 10) 0 (svref ls 11) 0 (svref ls 12) 0)
    (setf $e 0 $b 4 $b0 4 $tr 0 $hb 0 $cp #'stop-success)))
(init-machine)
