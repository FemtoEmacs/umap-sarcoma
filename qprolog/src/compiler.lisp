;;;; compiler.lisp -- clauses -> Lisp closures ("machine code" for the WAM-style machine).
;;;;
;;;; A clause is split into CHUNKS at its user-predicate calls (as in the WAM).  Each
;;;; chunk becomes one Lisp function of no arguments that returns the next code to run:
;;;;   chunk 0   head unification (arguments come from $A) + goals up to the first call
;;;;   chunk k   what follows the k-th call; its address is the continuation stored in $CP
;;;; Variables that live in one chunk are Lisp locals; the others ("permanent") live
;;;; in the environment frame on the local stack.  The last call is a jump after the
;;;; frame has been popped (last-call optimisation).

(in-package :qp)
(engine-policy)

;;; ------------------------------------------------------------------ goal tags
(defvar *tags* (make-hash-table :test 'equal))
(defun deftags (tag arity &rest names)
  (dolist (n names) (setf (gethash (cons n arity) *tags*) tag)))

(deftags :cut 0 "!")
(deftags :true 0 "TRUE")
(deftags :fail 0 "FAIL" "FALSE")
(deftags :realcut 0 "%CUT")
(deftags :not 1 "\\+" "NOT")
(deftags :once 1 "ONCE")
(deftags :ignore 1 "IGNORE")
(deftags :forall 2 "FORALL")
(deftags :unify 2 "UNIFY")
(deftags :is 2 "IS")
(deftags :cutto 1 "$CUTTO")
(deftags :cutb 1 "$CUTB")
(deftags :ar< 2 "<") (deftags :ar> 2 ">") (deftags :ar<= 2 "<=") (deftags :ar>= 2 ">=")
(deftags :ar= 2 "=") (deftags :ar/= 2 "/=")
(deftags :== 2 "==") (deftags :\\== 2 "\\==")
(deftags :@< 2 "@<") (deftags :@> 2 "@>") (deftags :@<= 2 "@=<") (deftags :@>= 2 "@>=")
(deftags :var 1 "VAR") (deftags :nonvar 1 "NONVAR") (deftags :atom 1 "ATOM")
(deftags :number 1 "NUMBER") (deftags :integer 1 "INTEGER") (deftags :float 1 "FLOAT")
(deftags :atomic 1 "ATOMIC") (deftags :compound 1 "COMPOUND") (deftags :callable 1 "CALLABLE")
(deftags :is_list 1 "IS_LIST")

(defun tag-of (goal)
  "Tag of a goal template, or NIL for an ordinary predicate call."
  (let ((f (tpl-functor goal)))
    (and f (symbolp f) (gethash (cons (symbol-name f) (tpl-arity goal)) *tags*))))

(defun control-goal-p (g)
  (let ((f (tpl-functor g)))
    (and f (symbolp f)
         (or (eq f :or) (eq f :and)
             (member (tag-of g) '(:not :once :ignore :forall))
             (and (string= (symbol-name f) "CALL") (>= (tpl-arity g) 1))))))

(defun pure-test-tag-p (tag)
  (member tag '(:ar< :ar> :ar<= :ar>= :ar= :ar/= :== :\\== :@< :@> :@<= :@>=
                :var :nonvar :atom :number :integer :float :atomic :compound :callable :is_list :true)))

;;; ------------------------------------------------------------------ analysis helpers
(defun tpl-vars (tpl &optional acc)
  (cond ((tv-p tpl) (if (member tpl acc :test #'eq) acc (cons tpl acc)))
        ((tcell-p tpl) (tpl-vars (tcell-tail tpl) (tpl-vars (tcell-head tpl) acc)))
        ((tstr-p tpl) (let ((a acc)) (loop for x across (tstr-args tpl) do (setq a (tpl-vars x a))) a))
        (t acc)))

(defun flatten-conj (g)
  "Goal template -> list of goal templates (:and flattened, TRUE dropped)."
  (cond ((and (or (tstr-p g) (simple-vector-p g)) (eq (tpl-functor g) :and))
         (loop for x in (tpl-args g) append (flatten-conj x)))
        ((eq g 'true) nil)
        ((and (symbolp g) g (eq (tag-of g) :true)) nil)
        (t (list g))))

(defun mk-goal (functor &rest args)
  (cond ((null args) functor)
        ((some #'template-p args) (make-tstr functor (coerce args 'simple-vector)))
        (t (coerce (cons functor args) 'simple-vector))))

(defvar *cut-marker* '%cut)

;;; ------------------------------------------------------------------ aux predicates
(defvar *aux-counter* 0)

(defun make-aux (clauses shared)
  "CLAUSES: list of goal-lists.  SHARED: list of tv passed as arguments.  Returns the pred."
  (let* ((name (make-symbol (format nil "$AUX~D" (incf *aux-counter*))))
         (p (make-pred name (length shared))))
    (dolist (body clauses)
      (add-clause-tpl p shared body 0))
    p))

(defun parse-arms (elems)
  "(c -> t c2 -> t2 e) -> list of (cond-goals . then-goals); plain arm has cond :none."
  (let ((arms nil))
    (loop while elems
          do (let ((x (pop elems)))
               (if (and elems (symbolp (car elems)) (car elems) (string= (symbol-name (car elems)) "->"))
                   (progn (pop elems) (push (cons (flatten-conj x) (flatten-conj (pop elems))) arms))
                   (push (cons :none (flatten-conj x)) arms))))
    (nreverse arms)))

(defun replace-user-cuts (goals cb)
  (mapcar (lambda (g) (if (eq (tag-of g) :cut) (mk-goal '$cutto cb) g)) goals))

(defun goals-have-cut (goals)
  (some (lambda (g) (eq (tag-of g) :cut)) goals))

;;; ------------------------------------------------------------------ normalisation
;;; A normalised goal is one of
;;;   (:cut) (:fail) (:unify a b) (:is a e) (:test tag args) (:det fn args) (:call pred args)
;;;   (:ite test-descs then-descs else-descs) (:not test-descs) (:cutb tv) (:cutto tv)

(defvar *occ*)        ; tv -> number of top-level positions (head or goal) it occurs in

(defun shared-vars (g)
  (remove-if-not (lambda (v) (>= (gethash v *occ* 0) 2)) (reverse (tpl-vars g))))

(defun norm-goals (goals)
  (loop for g in goals append (norm-goal g)))

(defun inline-only-p (descs)
  (every (lambda (d) (member (car d) '(:cut :fail :unify :is :test :det :cutto :cutb))) descs))

(defun pure-descs-p (descs)
  (every (lambda (d) (eq (car d) :test)) descs))

(defun norm-goal (g)
  (when (tv-p g)                                  ; a variable goal means call(G)
    (return-from norm-goal (list (list :call (get-pred (intern "CALL" :qp) 1) (list g)))))
  (let ((tag (tag-of g)) (args (tpl-args g)))
    (case tag
      ((:true) nil)
      ((:cut :realcut) (list (list :cut)))
      (:fail (list (list :fail)))
      (:cutto (list (list :cutto (first args))))
      (:cutb (list (list :cutb (first args))))
      (:unify (list (list :unify (first args) (second args))))
      (:is (list (list :is (first args) (second args))))
      ((:ar< :ar> :ar<= :ar>= :ar= :ar/= :== :\\== :@< :@> :@<= :@>=
        :var :nonvar :atom :number :integer :float :atomic :compound :callable :is_list)
       (list (list :test tag args)))
      (:not (norm-negation (flatten-conj (first args)) g))
      (:once (norm-or (list (cons (flatten-conj (first args)) nil)) g :once))
      (:ignore (norm-or (list (cons (flatten-conj (first args)) nil) (cons :none nil)) g :ignore))
      (:forall
       (norm-negation (list (first args) (mk-goal '\\+ (second args))) g))
      (t
       (let ((f (tpl-functor g)))
         (cond
           ((eq f :and) (norm-goals (flatten-conj g)))
           ((eq f :or) (norm-or (parse-arms args) g :or))
           ((and (symbolp f) (string= (symbol-name f) "CALL"))
            (norm-call g args))
           (t (norm-plain g))))))))

(defun norm-plain (g)
  (let* ((f (tpl-functor g)) (args (tpl-args g)))
    (unless (and f (symbolp f)) (error "not callable: ~S" g))
    (cond
      ;; arg/3 with a literal integer index is deterministic
      ((and (string= (symbol-name f) "ARG") (= (length args) 3) (integerp (first args)))
       (list (list :det (pred-det (get-pred (intern "%ARG" :qp) 3)) args)))
      (t
       (let ((p (get-pred f (length args))))
         (if (and (pred-det p) (not (pred-dynamic p)))
             (list (list :det (pred-det p) args))
             (list (list :call p args))))))))

(defun norm-call (g args)
  (declare (ignorable g))
  (let ((goal (first args)) (extra (rest args)))
    (cond
      ((and (not (tv-p goal)) (null extra))
       ;; call(G) with G known: opaque to cut
       (let* ((shared (shared-vars g))
              (p (make-aux (list (flatten-conj goal)) shared)))
         (list (list :call p shared))))
      ((and (not (tv-p goal)) (symbolp (tpl-functor goal)) (tpl-functor goal)
            (not (control-goal-p goal)))
       (norm-goal (append-args goal extra)))
      (t (list (list :call (get-pred (intern "CALL" :qp) (length args)) args))))))

(defun append-args (goal extra)
  (apply #'mk-goal (tpl-functor goal) (append (tpl-args goal) extra)))

(defun norm-negation (conj g)
  (let ((descs (norm-goals conj)))
    (if (and descs (pure-descs-p descs))
        (list (list :not descs))
        (let* ((shared (shared-vars g))
               (p (make-aux (list (append conj (list (list-marker-cut) (mk-goal 'fail)))
                                  nil)
                            shared)))
          (list (list :call p shared))))))

(defun list-marker-cut () *cut-marker*)

(defun norm-or (arms g kind)
  "ARMS: list of (cond-goals . then-goals), cond :none for a plain arm.  KIND :or :once :ignore."
  ;; inline (C -> T ; E) and (C -> T) when C is a pure test and T, E are inline goals
  (when (and (eq kind :or) (<= 1 (length arms) 2)
             (not (eq (car (first arms)) :none))
             (or (= (length arms) 1) (eq (car (second arms)) :none)))
    (let ((test (norm-goals (car (first arms))))
          (then (norm-goals (cdr (first arms))))
          (else (if (= (length arms) 2) (norm-goals (cdr (second arms))) (list (list :fail)))))
      (when (and test (pure-descs-p test) (inline-only-p then) (inline-only-p else))
        (return-from norm-or (list (list :ite test then else))))))
  (let* ((shared (shared-vars g))
         (needs-cb (and (eq kind :or) (loop for a in arms thereis (goals-have-cut (cdr a)))))
         (cb (and needs-cb (make-tv 0)))
         (params (if cb (cons cb shared) shared))
         (clauses
           (loop for (c . th) in arms
                 collect (let ((th (if cb (replace-user-cuts th cb) th)))
                           (if (eq c :none) th (append c (list *cut-marker*) th))))))
    (let ((p (make-aux clauses params)))
      (append (when cb (list (list :cutb cb)))
              (list (list :call p params))))))

;;; ------------------------------------------------------------------ compile-time variables
(defstruct (cvar (:constructor make-cvar (tv)))
  tv (perm nil) (yidx 0 :type fixnum) (sym nil) (seen nil) (count 0 :type fixnum)
  (chunks nil) (void nil))

(defvar *cvars*)
(defvar *has-env*)
(defvar *nperm*)

(defun cv (tv) (gethash tv *cvars*))

(defun note-occ (tpl chunk)
  (cond ((tv-p tpl)
         (let ((c (or (gethash tpl *cvars*) (setf (gethash tpl *cvars*) (make-cvar tpl)))))
           (incf (cvar-count c))
           (pushnew chunk (cvar-chunks c))))
        ((tcell-p tpl) (note-occ (tcell-head tpl) chunk) (note-occ (tcell-tail tpl) chunk))
        ((tstr-p tpl) (loop for x across (tstr-args tpl) do (note-occ x chunk)))))

(defun desc-templates (d)
  (ecase (car d)
    ((:cut :fail) nil)
    ((:unify :is) (list (second d) (third d)))
    (:test (third d))
    (:det (third d))
    (:call (third d))
    ((:cutb :cutto) (list (second d)))
    (:not (loop for x in (second d) append (desc-templates x)))
    (:ite (loop for x in (append (second d) (third d) (fourth d)) append (desc-templates x)))))

;;; ------------------------------------------------------------------ code generation
(defvar *b0-form*)      ; form giving the cut barrier in the chunk being generated

(defun var-read (c)
  (if (cvar-perm c)
      `(svref $ls (the fixnum (+ e ,(+ +e-y+ (cvar-yidx c)))))
      (cvar-sym c)))

(defun var-write (c val)
  (if (cvar-perm c)
      `(setf (svref $ls (the fixnum (+ e ,(+ +e-y+ (cvar-yidx c))))) ,val)
      `(setq ,(cvar-sym c) ,val)))

(defun save-seen ()
  (let ((l nil)) (maphash (lambda (k c) (declare (ignore k)) (when (cvar-seen c) (push c l))) *cvars*) l))

(defun restore-seen (l)
  (maphash (lambda (k c) (declare (ignore k)) (setf (cvar-seen c) nil)) *cvars*)
  (dolist (c l) (setf (cvar-seen c) t)))

(defun gen-build (tpl)
  "Expression that builds the runtime term for TPL; marks first occurrences as seen."
  (cond ((tv-p tpl)
         (let ((c (cv tpl)))
           (cond ((cvar-void c) '(new-var))
                 ((cvar-seen c) (var-read c))
                 (t (setf (cvar-seen c) t) (var-write c '(new-var))))))
        ((tcell-p tpl)
         (let* ((h (gen-build (tcell-head tpl))) (tl (gen-build (tcell-tail tpl))))
           `(cons ,h ,tl)))
        ((tstr-p tpl)
         (let ((args (loop for x across (tstr-args tpl) collect (gen-build x))))
           `(vector ',(tstr-functor tpl) ,@args)))
        (t `',tpl)))

(defun const-test-form (c v)
  (if (symbolp c) `(eq ,v ',c) `(eql ,v ',c)))

(defun gen-head (tpl expr)
  "Form unifying the runtime term EXPR with template TPL (fails with (fail!))."
  (cond
    ((tv-p tpl)
     (let ((c (cv tpl)))
       (cond ((cvar-void c) nil)
             ((cvar-seen c) `(unless (unify ,(var-read c) ,expr) (fail!)))
             (t (setf (cvar-seen c) t) (var-write c expr)))))
    ((or (null tpl) (symbolp tpl) (numberp tpl))
     (let ((v (gensym "V")))
       `(let ((,v (deref ,expr)))
          (cond (,(const-test-form tpl v) nil)
                ((pv-p ,v) (bind ,v ',tpl))
                (t (fail!))))))
    ((or (consp tpl) (simple-vector-p tpl) (stringp tpl))       ; ground compound
     `(unless (unify ',tpl ,expr) (fail!)))
    ((tcell-p tpl)
     (let* ((v (gensym "V")) (h (gensym "H")) (tl (gensym "T")) (s0 (save-seen))
            (read-form `(let ((,h (car (the cons ,v))) (,tl (cdr (the cons ,v))))
                          ,(gen-head (tcell-head tpl) h)
                          ,(gen-head (tcell-tail tpl) tl)))
            (s1 (save-seen)))
       (restore-seen s0)
       (let ((write-form (gen-build tpl)))
         (restore-seen (union s1 (save-seen)))
         `(let ((,v (deref ,expr)))
            (cond ((consp ,v) ,read-form)
                  ((pv-p ,v) (bind ,v ,write-form))
                  (t (fail!)))))))
    ((tstr-p tpl)
     (let* ((v (gensym "V")) (args (tstr-args tpl)) (n (length args))
            (syms (loop repeat n collect (gensym "A"))) (s0 (save-seen))
            (read-form `(let ,(loop for s in syms for i from 1 collect `(,s (svref ,v ,i)))
                          ,@(loop for s in syms for x across args collect (gen-head x s))))
            (s1 (save-seen)))
       (restore-seen s0)
       (let ((write-form (gen-build tpl)))
         (restore-seen (union s1 (save-seen)))
         `(let ((,v (deref ,expr)))
            (cond ((and (simple-vector-p ,v) (= (length ,v) ,(1+ n)) (eq (svref ,v 0) ',(tstr-functor tpl)))
                   ,read-form)
                  ((pv-p ,v) (bind ,v ,write-form))
                  (t (fail!)))))))
    (t (error "gen-head: ~S" tpl))))

;;; arithmetic
(defun gen-arith (tpl)
  (cond ((numberp tpl) tpl)
        ((tv-p tpl)
         (let ((c (cv tpl)))
           (if (or (cvar-void c) (not (cvar-seen c)))
               '(inst-err)
               `(ar-val ,(var-read c)))))
        ((or (tstr-p tpl) (simple-vector-p tpl))
         (let* ((f (tpl-functor tpl)) (args (tpl-args tpl)) (n (length args))
                (name (symbol-name f)))
           (flet ((a (i) (gen-arith (nth i args))))
             (cond
               ((and (= n 2) (string= name "+")) `(ar+ ,(a 0) ,(a 1)))
               ((and (= n 2) (string= name "-")) `(ar- ,(a 0) ,(a 1)))
               ((and (= n 2) (string= name "*")) `(ar* ,(a 0) ,(a 1)))
               ((and (= n 2) (string= name "/")) `(ar-div ,(a 0) ,(a 1)))
               ((and (= n 2) (string= name "//")) `(ar-intdiv ,(a 0) ,(a 1)))
               ((and (= n 2) (string-equal name "MOD")) `(ar-mod ,(a 0) ,(a 1)))
               ((and (= n 2) (string-equal name "REM")) `(ar-rem ,(a 0) ,(a 1)))
               ((and (= n 2) (string= name ">>")) `(ash (ar-int ,(a 0)) (- (the fixnum (ar-int ,(a 1))))))
               ((and (= n 2) (string= name "<<")) `(ash (ar-int ,(a 0)) (the fixnum (ar-int ,(a 1)))))
               ((and (= n 2) (string= name "/\\")) `(logand (ar-int ,(a 0)) (ar-int ,(a 1))))
               ((and (= n 2) (string= name "\\/")) `(logior (ar-int ,(a 0)) (ar-int ,(a 1))))
               ((and (= n 2) (string-equal name "MIN")) `(let ((x ,(a 0)) (y ,(a 1))) (if (< y x) y x)))
               ((and (= n 2) (string-equal name "MAX")) `(let ((x ,(a 0)) (y ,(a 1))) (if (> y x) y x)))
               ((and (= n 1) (string= name "-")) `(- (the number ,(a 0))))
               ((and (= n 1) (string-equal name "ABS")) `(abs (the number ,(a 0))))
               ((= n 1) `(ar-apply1 ,name ,(a 0) nil))
               ((= n 2) `(ar-apply2 ,name ,(a 0) ,(a 1) nil))
               (t `(ar-eval ,(gen-build tpl)))))))
        ((symbolp tpl) `(ar-eval ',tpl))
        (t `(ar-eval ,(gen-build tpl)))))

(defun gen-test-form (tag args)
  "Boolean form for a pure test (no bindings)."
  (flet ((b (i) (gen-build (nth i args))))
    (case tag
      (:ar< `(let* ((x ,(gen-arith (nth 0 args))) (y ,(gen-arith (nth 1 args)))) (ar< x y)))
      (:ar> `(let* ((x ,(gen-arith (nth 0 args))) (y ,(gen-arith (nth 1 args)))) (ar> x y)))
      (:ar<= `(let* ((x ,(gen-arith (nth 0 args))) (y ,(gen-arith (nth 1 args)))) (ar<= x y)))
      (:ar>= `(let* ((x ,(gen-arith (nth 0 args))) (y ,(gen-arith (nth 1 args)))) (ar>= x y)))
      (:ar= `(let* ((x ,(gen-arith (nth 0 args))) (y ,(gen-arith (nth 1 args)))) (ar= x y)))
      (:ar/= `(let* ((x ,(gen-arith (nth 0 args))) (y ,(gen-arith (nth 1 args)))) (ar/= x y)))
      (:== `(let* ((x ,(b 0)) (y ,(b 1))) (term== x y)))
      (:\\== `(let* ((x ,(b 0)) (y ,(b 1))) (not (term== x y))))
      (:@< `(let* ((x ,(b 0)) (y ,(b 1))) (< (the fixnum (compare-terms x y)) 0)))
      (:@> `(let* ((x ,(b 0)) (y ,(b 1))) (> (the fixnum (compare-terms x y)) 0)))
      (:@<= `(let* ((x ,(b 0)) (y ,(b 1))) (<= (the fixnum (compare-terms x y)) 0)))
      (:@>= `(let* ((x ,(b 0)) (y ,(b 1))) (>= (the fixnum (compare-terms x y)) 0)))
      (:var `(pv-p (deref ,(b 0))))
      (:nonvar `(not (pv-p (deref ,(b 0)))))
      (:atom `(let ((x (deref ,(b 0)))) (and (symbolp x) t)))
      (:number `(numberp (deref ,(b 0))))
      (:integer `(integerp (deref ,(b 0))))
      (:float `(floatp (deref ,(b 0))))
      (:atomic `(let ((x (deref ,(b 0)))) (not (or (pv-p x) (consp x) (simple-vector-p x)))))
      (:compound `(let ((x (deref ,(b 0)))) (or (consp x) (simple-vector-p x))))
      (:callable `(let ((x (deref ,(b 0)))) (or (and (symbolp x) x) (simple-vector-p x))))
      (:is_list `(listp-term ,(b 0)))
      (:true t)
      (t (error "no test ~S" tag)))))

(defun gen-desc (d)
  "Forms for one inline goal descriptor (the CALL descriptor is handled by the chunk)."
  (ecase (car d)
    (:cut `((cut-to ,*b0-form*)))
    (:fail `((fail!)))
    (:cutb (list (gen-cutb (second d))))
    (:cutto `((cut-to (the fixnum ,(gen-build (second d))))))
    (:unify (list (gen-unify (second d) (third d))))
    (:is (list (gen-is (second d) (third d))))
    (:test `((unless ,(gen-test-form (second d) (third d)) (fail!))))
    (:not (let ((pre (pre-init-forms (second d))))
            `(,@pre (when (and ,@(mapcar (lambda (x) (gen-test-form (second x) (third x))) (second d))) (fail!)))))
    (:det `((unless (funcall (the function ',(second d)) ,@(mapcar #'gen-build (third d))) (fail!))))
    (:ite (list (gen-ite d)))))

(defun pre-init-forms (descs)
  "Initialise (as fresh variables) unseen variables that first occur inside pure tests."
  (let ((forms nil))
    (dolist (d descs)
      (dolist (tp (desc-templates d))
        (dolist (v (tpl-vars tp))
          (let ((c (cv v)))
            (when (and (not (cvar-void c)) (not (cvar-seen c)))
              (setf (cvar-seen c) t)
              (push (var-write c '(new-var)) forms))))))
    (nreverse forms)))

(defun gen-cutb (tv)
  (let ((c (cv tv)))
    (if (cvar-void c)
        nil
        (progn (setf (cvar-seen c) t)
               (if (cvar-perm c) (var-write c *b0-form*) `(setq ,(cvar-sym c) ,*b0-form*))))))

(defun first-occ-var (tpl)
  (and (tv-p tpl) (let ((c (cv tpl))) (and (not (cvar-void c)) (not (cvar-seen c)) c))))

(defun occurs-in-p (tv tpl)
  (member tv (tpl-vars tpl) :test #'eq))

(defun gen-unify (a b)
  (let ((ca (first-occ-var a)) (cb (first-occ-var b)))
    (cond ((and ca (not (occurs-in-p a b)))
           (let ((val (gen-build b))) (setf (cvar-seen ca) t) (var-write ca val)))
          ((and cb (not (occurs-in-p b a)))
           (let ((val (gen-build a))) (setf (cvar-seen cb) t) (var-write cb val)))
          ((and (tv-p a) (cvar-void (cv a))) (gen-build b))
          ((and (tv-p b) (cvar-void (cv b))) (gen-build a))
          (t (let* ((x (gen-build a)) (y (gen-build b))) `(unless (unify ,x ,y) (fail!)))))))

(defun gen-is (lhs expr)
  (let ((val (gen-arith expr)) (c (first-occ-var lhs)))
    (cond (c (setf (cvar-seen c) t) (var-write c val))
          ((and (tv-p lhs) (cvar-void (cv lhs))) val)
          (t `(unless (unify-num ,(gen-build lhs) ,val) (fail!))))))

(defun gen-ite (d)
  (destructuring-bind (test then else) (cdr d)
    (let* ((pre (pre-init-forms test))
           (test-form `(and ,@(mapcar (lambda (x) (gen-test-form (second x) (third x))) test)))
           (s0 (save-seen))
           (then-forms (mapcan #'gen-desc then))
           (s1 (save-seen)))
      (restore-seen s0)
      (let* ((else-forms (mapcan #'gen-desc else)) (s2 (save-seen)))
        ;; variables first bound in only one branch are given a fresh variable in the other
        (let ((only1 (set-difference s1 s2)) (only2 (set-difference s2 s1)))
          (dolist (c only2)
            (setf then-forms (append then-forms (list (if (cvar-perm c) (var-write c '(new-var)) `(setq ,(cvar-sym c) (new-var)))))))
          (dolist (c only1)
            (setf else-forms (append else-forms (list (if (cvar-perm c) (var-write c '(new-var)) `(setq ,(cvar-sym c) (new-var))))))))
        (restore-seen (union s1 s2))
        `(progn ,@pre (if ,test-form (progn ,@then-forms) (progn ,@else-forms)))))))

;;; ------------------------------------------------------------------ clause compilation
(defun partition-chunks (descs)
  "-> list of (inline-descs . call-desc-or-nil)"
  (let ((chunks nil) (cur nil))
    (dolist (d descs)
      (if (eq (car d) :call)
          (progn (push (cons (nreverse cur) d) chunks) (setq cur nil))
          (push d cur)))
    (when (or cur (null chunks))
      (push (cons (nreverse cur) nil) chunks))
    (nreverse chunks)))

(defun clause-form (head-args body)
  "Lisp form that evaluates to the entry function of the clause."
  (let* ((*cvars* (make-hash-table :test 'eq))
         (*occ* (make-hash-table :test 'eq))
         (goals (loop for g in body append (flatten-conj g))))
    ;; occurrence counts per top-level position, for aux-predicate parameter lists
    (dolist (a head-args) (dolist (v (tpl-vars a)) (incf (gethash v *occ* 0))))
    (dolist (g goals) (dolist (v (tpl-vars g)) (incf (gethash v *occ* 0))))
    (let* ((descs (norm-goals goals))
           (chunks (partition-chunks descs))
           (nchunks (length chunks))
           (*has-env* (> nchunks 1))
           (*nperm* 0))
      ;; variable analysis
      (dolist (a head-args) (note-occ a 0))
      (loop for ch in chunks for j from 0
            do (dolist (d (car ch)) (dolist (tp (desc-templates d)) (note-occ tp j)))
               (when (cdr ch) (dolist (tp (desc-templates (cdr ch))) (note-occ tp j))))
      (let ((k 0))
        (maphash (lambda (tv c)
                   (declare (ignore tv))
                   (cond ((= (cvar-count c) 1) (setf (cvar-void c) t))
                         ((> (length (cvar-chunks c)) 1)
                          (setf (cvar-perm c) t (cvar-yidx c) k) (incf k))
                         (t (setf (cvar-sym c) (gensym "X")))))
                 *cvars*)
        (setq *nperm* k))
      ;; generate chunk code in order
      (let ((lambdas nil))
        (loop for ch in chunks for j from 0
              do (let* ((lastp (= j (1- nchunks)))
                        (*b0-form* (if (zerop j) 'b0 `(the fixnum (svref $ls (+ e ,+e-cutb+)))))
                        (forms nil))
                   (when (zerop j)
                     (loop for a in head-args for i from 0
                           do (let ((f (gen-head a `(svref $a ,i)))) (when f (push f forms)))))
                   (dolist (d (car ch)) (dolist (f (gen-desc d)) (when f (push f forms))))
                   (let ((call (cdr ch)))
                     (if call
                         (push (gen-call call j lastp) forms)
                         (push (gen-proceed) forms)))
                   (let ((temps (let ((l nil))
                                  (maphash (lambda (tv c) (declare (ignore tv))
                                             (when (and (not (cvar-perm c)) (not (cvar-void c))
                                                        (eql (first (cvar-chunks c)) j))
                                               (push (cvar-sym c) l)))
                                           *cvars*)
                                  l)))
                     (push (chunk-lambda j (nreverse forms) temps) lambdas))))
        ;; lambdas is in reverse chunk order: last chunk first
        (let ((bindings nil) (chunk0 nil))
          (loop for lam in lambdas for j downfrom (1- nchunks)
                do (if (zerop j)
                       (setq chunk0 lam)
                       (push `(,(k-sym j) ,lam) bindings)))
          ;; bindings must be ordered last chunk first for LET*
          `(let* ,(nreverse bindings) ,chunk0))))))

(defun k-sym (j) (intern (format nil "K~D" j) :qp))

(defun chunk-lambda (j forms temps)
  `(lambda ()
     (declare ,*clause-policy*)
     (block %c
       (macrolet ((fail! () '(return-from %c (backtrack))))
         (let* (,@(when (zerop j) `((b0 $b0)))
                ,@(cond ((and (zerop j) *has-env*) `((e (alloc-env ,*nperm*))))
                        ((zerop j) nil)
                        (t `((e $e))))
                ,@(mapcar (lambda (s) `(,s nil)) temps))
           (declare (ignorable ,@(when (zerop j) '(b0)) ,@(when (or *has-env* (plusp j)) '(e)) ,@temps)
                    ,@(when (or *has-env* (plusp j)) '((type fixnum e)))
                    ,@(when (zerop j) '((type fixnum b0))))
           ,@forms)))))

(defun gen-call (call j lastp)
  (let* ((p (second call)) (args (third call))
         (arg-forms (loop for a in args for i from 0
                          collect `(setf (svref $a ,i) ,(gen-build a)))))
    (when (> (length args) +max-arity+) (error "arity too large"))
    `(progn
       ,@arg-forms
       ,@(cond ((not lastp) `((setf $cp ,(k-sym (1+ j)))))
               (*has-env* `((setf $cp (the function (svref $ls (+ e ,+e-cp+)))
                                  $e (the fixnum (svref $ls (+ e ,+e-prev+))))))
               (t nil))
       (setf $b0 $b)
       (return-from %c (pred-entry (the pred ',p))))))

(defun gen-proceed ()
  (if *has-env*
      `(progn (setf $cp (the function (svref $ls (+ e ,+e-cp+)))
                    $e (the fixnum (svref $ls (+ e ,+e-prev+))))
              (return-from %c $cp))
      `(return-from %c $cp)))

