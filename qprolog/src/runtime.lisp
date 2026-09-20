;;;; runtime.lisp -- compiling predicates, first-argument dispatch, meta-call, nested runs,
;;;; and the small runtime helpers the generated code calls.
(in-package :qp)
(engine-policy)

(proclaim '(sb-ext:muffle-conditions sb-ext:compiler-note))

;;; ------------------------------------------------------------------ helpers for generated code
(defun term== (a b) (eql 0 (compare-terms a b)))

(defun unify-num (lhs val)
  (let ((l (deref lhs)))
    (if (pv-p l) (bind l val) (eql l val))))

(defun listp-term (x)
  (let ((x (deref x)))
    (loop (cond ((null x) (return t))
                ((consp x) (setq x (deref (cdr x))))
                (t (return nil))))))

;;; ------------------------------------------------------------------ compiling
(defun compile-form (form)
  (let ((*error-output* (make-broadcast-stream)))
    (handler-bind ((warning #'muffle-warning))
      (funcall (compile nil `(lambda () ,form))))))

(defun compile-clause-fn (c)
  (compile-form (clause-form (clause-head-args c) (clause-body c))))

(defun compile-dyn-clause (c)
  (setf (clause-fn c) (compile-clause-fn c)))

(defun clause-list (p)
  (loop for c = (pred-first p) then (clause-next c) while c collect c))

(defun compile-pred (p)
  (let* ((clauses (clause-list p))
         (fns (mapcar (lambda (c) (or (clause-fn c) (setf (clause-fn c) (compile-clause-fn c))))
                      clauses)))
    (setf (pred-compiled p) t
          (pred-entry p) (make-dispatcher p clauses fns))))

(defun unknown-pred (p)
  (throw-error (vector 'existence_error 'procedure (vector '/ (pred-name p) (pred-arity p)))))

(defun enter-pred (p)
  "Entry stub: first call of a predicate that has not been compiled yet."
  (cond ((pred-dynamic p)
         (setf (pred-entry p) (lambda () (dyn-entry p)))
         (dyn-entry p))
        ((pred-first p) (compile-pred p) (funcall (the function (pred-entry p))))
        ((pred-defined p) (backtrack))
        (t (unknown-pred p))))

;;; ------------------------------------------------------------------ dispatch
(defun make-dispatcher (p clauses fns)
  (let ((n (length clauses)) (arity (pred-arity p)))
    (cond ((= n 0) (lambda () (backtrack)))
          ((= n 1) (first fns))
          ((or (= arity 0) (every (lambda (c) (eq (clause-key c) :var)) clauses))
           (let ((cands (coerce fns 'simple-vector)))
             (lambda () (call-cands cands arity))))
          (t (index-dispatcher arity clauses fns)))))

(defun cand-vector (clauses fns key)
  "Functions of the clauses whose first-argument key is KEY or :VAR (KEY :ALL = every clause)."
  (coerce (loop for c in clauses for f in fns
                when (or (eq key :all) (eq (clause-key c) :var) (eql (clause-key c) key))
                  collect f)
          'simple-vector))

(defun index-dispatcher (arity clauses fns)
  (let* ((keys (remove-duplicates (loop for c in clauses unless (eq (clause-key c) :var) collect (clause-key c))
                                  :test #'eql :from-end t))
         (all (cand-vector clauses fns :all))
         (none (cand-vector clauses fns '%none))
         (tab (mapcar (lambda (k) (cons k (cand-vector clauses fns k))) keys))
         (nkeys (length keys))
         (kv (coerce keys 'simple-vector))
         (cv (coerce (mapcar #'cdr tab) 'simple-vector))
         (h (when (> nkeys 6)
              (let ((h (make-hash-table :test 'eql)))
                (dolist (e tab) (setf (gethash (car e) h) (cdr e)))
                h))))
    (declare (simple-vector all none kv cv) (fixnum nkeys))
    (macrolet ((finish (cands)
                 `(let ((c ,cands))
                    (declare (simple-vector c))
                    (case (length c)
                      (0 (backtrack))
                      (1 (svref c 0))
                      (t (call-cands c arity))))))
      (if h
          (lambda ()
            (let ((a0 (deref (svref $a 0))))
              (setf (svref $a 0) a0)
              (cond ((pv-p a0) (finish all))
                    ((consp a0) (finish (or (gethash :list h) none)))
                    ((simple-vector-p a0) (finish (or (gethash (svref a0 0) h) none)))
                    ((stringp a0) (finish all))
                    (t (finish (or (gethash a0 h) none))))))
          (lambda ()
            (let ((a0 (deref (svref $a 0))))
              (setf (svref $a 0) a0)
              (cond ((pv-p a0) (finish all))
                    ((stringp a0) (finish all))
                    (t (let ((k (cond ((consp a0) :list)
                                      ((simple-vector-p a0) (svref a0 0))
                                      (t a0))))
                         (dotimes (i nkeys (finish none))
                           (when (eql (svref kv i) k) (return (finish (svref cv i))))))))))))))

;;; ------------------------------------------------------------------ builtin definition
(defun det-entry (fn arity)
  (declare (function fn) (fixnum arity))
  (macrolet ((mk (n)
               `(lambda () (if (funcall fn ,@(loop for i below n collect `(svref $a ,i))) $cp (backtrack)))))
    (case arity
      (0 (mk 0)) (1 (mk 1)) (2 (mk 2)) (3 (mk 3)) (4 (mk 4)) (5 (mk 5)) (6 (mk 6))
      (t (lambda ()
           (if (apply fn (loop for i below arity collect (svref $a i))) $cp (backtrack)))))))

(defun def-det (name arity fn)
  (let ((p (get-pred name arity)))
    (setf (pred-det p) fn (pred-defined p) t (pred-library p) t
          (pred-entry p) (det-entry fn arity))
    p))

(defmacro defdet (name args &body body)
  "A deterministic builtin: BODY returns true (success) or NIL (failure)."
  `(def-det ',name ,(length args) (lambda ,args (declare (ignorable ,@args)) ,@body)))

(defun def-lisp (name arity entry)
  "A builtin whose ENTRY function is called with the machine state (args in $A)."
  (let ((p (get-pred name arity)))
    (setf (pred-lisp p) t (pred-defined p) t (pred-library p) t (pred-entry p) entry)
    p))

(defmacro deflisp (name arity &body body)
  `(def-lisp ',name ,arity (lambda () ,@body)))

;;; ------------------------------------------------------------------ meta-call
(defun control-functor-p (name n)
  (declare (ignorable n))
  (or (eq name :and) (eq name :or)))

(defun goal-parts (g)
  (cond ((pv-p g) (inst-err))
        ((symbolp g) (values g nil))
        ((simple-vector-p g) (values (svref g 0) (loop for i from 1 below (length g) collect (svref g i))))
        (t (type-err 'callable g))))

(defun call-control (goal)
  "Meta-call of a control construct: compile it to a one-off auxiliary predicate."
  (let* ((*aux-counter* *aux-counter*))
    (multiple-value-bind (tp map) (term->template goal)
      (let* ((tpl (funcall tp goal))
             (pairs (let ((l nil)) (maphash (lambda (pv tv) (push (cons tv pv) l)) map)
                      (sort l #'< :key (lambda (x) (tv-idx (car x))))))
             (shared (mapcar #'car pairs))
             (p (make-aux (list (flatten-conj tpl)) shared)))
        (loop for (nil . pv) in pairs for i from 0 do (setf (svref $a i) pv))
        (setf $b0 $b)
        (pred-entry p)))))

(defun meta-call (goal extra)
  "Set up a call of GOAL with EXTRA arguments; returns the code to run."
  (let ((g (deref goal)))
    (multiple-value-bind (name args) (goal-parts g)
      (let ((args (if extra (append args extra) args)))
        (if (control-functor-p name (length args))
            (if extra
                (call-control (apply #'vector name args))
                (call-control g))
            (let ((p (get-pred name (length args))))
              (loop for a in args for i fixnum from 0 do (setf (svref $a i) a))
              (setf $b0 $b)
              (pred-entry p)))))))

(macrolet ((def-call (n)
             `(def-lisp 'call ,n
                (lambda ()
                  (meta-call (svref $a 0) (list ,@(loop for i from 1 below n collect `(svref $a ,i))))))))
  (def-call 1) (def-call 2) (def-call 3) (def-call 4) (def-call 5) (def-call 6) (def-call 7))

;;; ------------------------------------------------------------------ nested runs
(defun solve-iter (goal on-solution)
  "Run GOAL to exhaustion in a nested run.  ON-SOLUTION is called at each solution and may
return :STOP.  All bindings are undone at the end."
  (declare (function on-solution))
  (let ((saved-e $e) (saved-b $b) (saved-cp $cp) (saved-b0 $b0) (saved-hb $hb)
        (barrier (push-choice #'stop-fail nil 0 0)))
    (declare (fixnum saved-e saved-b saved-b0 saved-hb barrier))
    (setf $cp #'stop-success)
    (unwind-protect
         (let ((ok (run (lambda () (meta-call goal nil)))))
           (loop while ok
                 do (when (eq (funcall on-solution) :stop) (return))
                    (setq ok (run #'backtrack))))
      (undo-trail (the fixnum (ls (+ barrier +c-tr+))))
      (setf $b saved-b $e saved-e $cp saved-cp $b0 saved-b0 $hb saved-hb))
    nil))

(defun solve-once (goal)
  "Run GOAL once in a nested run; bindings are kept.  Returns true on success."
  (let ((saved-e $e) (saved-b $b) (saved-cp $cp) (saved-b0 $b0) (saved-hb $hb)
        (barrier (push-choice #'stop-fail nil 0 0)))
    (declare (fixnum saved-e saved-b saved-b0 saved-hb barrier))
    (setf $cp #'stop-success)
    (let ((ok nil))
      (unwind-protect
           (setq ok (run (lambda () (meta-call goal nil))))
        (if ok
            (setf $b saved-b $hb saved-hb)          ; keep bindings (and their trail entries)
            (progn (undo-trail (the fixnum (ls (+ barrier +c-tr+)))) (setf $b saved-b $hb saved-hb)))
        (setf $e saved-e $cp saved-cp $b0 saved-b0))
      ok)))

;;; ------------------------------------------------------------------ query API
(defun prepare-query (goal)
  "Surface-syntax GOAL -> (template . nvars)."
  (multiple-value-bind (tpl n) (convert-clause-term goal)
    (cons tpl n)))

(defun query-frame (q) (make-array (cdr q) :initial-element '%unset))

(defun run-query (q &optional (all nil))
  "Run a prepared query.  Returns (values success-p solutions); with ALL, every solution as
Lisp data (terms COPIED), otherwise the first solution's variable bindings."
  (let* ((frame (query-frame q))
         (term (instantiate (car q) frame))
         (sols nil) (ok nil))
    (init-machine)
    (solve-iter term (lambda ()
                       (setq ok t)
                       (push (term->lisp term) sols)
                       (if all nil :stop)))
    (values ok (nreverse sols))))

(defun solve-one (goal) (run-query (prepare-query goal)))
(defun solve-all (goal) (run-query (prepare-query goal) t))

(defun load-qp (file)
  "Load a qprolog program: a .lisp file of (<- ...) forms, or (by extension) a .pl file of
ordinary Prolog text, which is translated on the fly (see consult.lisp)."
  (if (equalp (pathname-type (pathname file)) "pl")
      (consult-pl file)
      (let ((*package* (find-package :qp)) (*read-default-float-format* 'double-float))
        (with-open-file (s file)
          (loop for form = (read s nil :eof) until (eq form :eof) do (eval form))))))

(defun solve-collect (goal var-syms &optional (limit 101))
  "Run GOAL (surface syntax); return up to LIMIT solutions, each the list of runtime terms
(copied) that the variables VAR-SYMS (symbols) are bound to."
  (let* ((*vt* (make-hash-table :test 'eq)) (*nv* 0)
         (tpl (conv goal))
         (frame (make-array *nv* :initial-element '%unset))
         (term (instantiate tpl frame))
         (vars (mapcar (lambda (s) (let ((tv (gethash s *vt*))) (and tv (svref frame (tv-idx tv))))) var-syms))
         (sols nil) (n 0))
    (init-machine)
    (solve-iter term (lambda ()
                       (push (copy-term (mapcar (lambda (v) (if v v nil)) vars)) sols)
                       (if (>= (incf n) limit) :stop nil)))
    (nreverse sols)))

;;; ------------------------------------------------------------------ catch / throw
;;; catch(G, C, R) pushes a special choice frame (alternative CATCH-ALT: just fail through),
;;; then runs G with the continuation CATCH-EXIT, which discards the frame if it is still the
;;; newest one.  A Prolog error unwinds the choice stack to the newest catch frame of the
;;; current run whose catcher unifies with the (copied) ball.
(defun catch-alt () (pop-choice) (backtrack))

(defun catch-exit ()
  (let* ((e $e) (cb (svref $ls (+ e +e-y+))))
    (declare (fixnum e cb))
    (when (= $b cb) (pop-choice))
    (setf $cp (svref $ls (+ e +e-cp+)) $e (svref $ls (+ e +e-prev+)))
    $cp))

(deflisp catch 3
  (let ((goal (svref $a 0)) (catcher (svref $a 1)) (rec (svref $a 2)))
    (let ((cb (push-choice #'catch-alt (cons catcher rec) nil 0)))
      (let ((e (alloc-env 1)))
        (setf (svref $ls (+ e +e-y+)) cb)
        (setf $cp #'catch-exit)
        (meta-call goal nil)))))

(deflisp throw 1
  (let ((ball (deref (svref $a 0))))
    (when (pv-p ball) (inst-err))
    (error 'prolog-error :term (copy-term ball))))

(defun handle-throw (c)
  (let ((ball (copy-term (prolog-error-term c))))
    (loop
      (let* ((b $b) (ls $ls) (alt (svref ls (+ b +c-alt+))))
        (declare (fixnum b))
        (when (eq alt #'stop-fail) (error c))             ; barrier of this run: propagate outwards
        (undo-trail (svref ls (+ b +c-tr+)))
        (setf $e (svref ls (+ b +c-e+)) $cp (svref ls (+ b +c-cp+)))
        (pop-choice)
        (when (eq alt #'catch-alt)
          (let ((cr (svref ls (+ b +c-s1+))) (mark $tr))
            (setf $hb $vc)
            (if (unify (car cr) ball)
                (progn (setf $hb (the fixnum (svref $ls (+ $b +c-vc+))))
                       (return (meta-call (cdr cr) nil)))
                (progn (undo-trail mark)
                       (setf $hb (the fixnum (svref $ls (+ $b +c-vc+)))))))))))) 
