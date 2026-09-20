;;;; pl2lispy.lisp -- translate a SWI-syntax Prolog program, WITH full operator
;;;; syntax, into lispy-Prolog (<- ...) clauses.
;;;;
;;;;   sbcl --noinform --non-interactive --load bench/pl2lispy.lisp \
;;;;        --eval '(pl2lispy:translate-file "bench/swi/tak.pl" "bench/lispy/tak.lisp")'
;;;;   ... or  (pl2lispy:translate-all "bench/swi/" "bench/lispy/")
;;;;
;;;; Why a second translator next to p99/gen-lispy.lisp?  gen-lispy reads
;;;; clauses with rollout/edinburgh-reader.lisp, which deliberately has NO
;;;; operator table (`X is A+B`, `\==`, `A/B` as data, `:- op(...)` ... do not
;;;; parse).  The classical benchmarks use all of that, so this file carries
;;;; its own small standard operator-precedence reader (Pratt style, SWI's
;;;; default operator table, honouring `:- op/3` directives) and prints the
;;;; result in the bracket syntax the engine is written in:
;;;;
;;;;   head :- a, b.            (<- head a b)
;;;;   X = Y                    (unify ?x ?y)
;;;;   X is A+B*2               (is ?x (+ ?a (* ?b 2)))
;;;;   A =:= B  A =\= B  A =< B (= a b) (/= a b) (<= a b)
;;;;   ( C -> T ; E )           (:or c -> t e)        ; (:and g...) for a conjunction
;;;;   \+ G                     (\+ g)
;;;;   [H|T]   []               (?h . ?t)   ()
;;;;   f(a, g(X))               (f a (g ?x))
;;;;   :- dynamic p/1.          (declare-dynamic '(/ p 1))
;;;;
;;;; Variables keep their names (`?Name`); two names that differ only in case
;;;; (`Xs`/`XS`) get a numeric suffix because the Lisp reader folds case.
;;;; Unquoted atoms are folded like everywhere else in the engine; quoted atoms
;;;; keep their case (`'Foo'` -> |Foo|), and the atom `nil` is written |nil|
;;;; so it is not mistaken for the empty list.  An atom starting with `?` (the
;;;; engine would read it as a variable) is renamed with a `$q` prefix everywhere.
;;;;
;;;; DCG rules (`-->`, with `{}`, `!`, terminals, `call//N`) are expanded the usual
;;;; way.  Not supported: pushback, `phrase/2,3` at run time.  SWI's
;;;; single-sided-unification rule `Head => Body` is translated as
;;;; `Head :- !, Body` and the determinism check `$Goal` / `$` as `Goal` / `!`
;;;; (an approximation; see bench/README.md).

(defpackage :pl2lispy (:use :cl) (:export #:translate-file #:translate-all #:translate-text #:translate-query))
(in-package :pl2lispy)

;;; ------------------------------------------------------------------ operators

(defvar *ops* (make-hash-table :test 'equal)
  "name -> list of (kind priority type); kind is :prefix, :infix or :postfix.")

(defun add-op (prio type name)
  (let* ((type (string-downcase type))
         (kind (cond ((member type '("fx" "fy") :test #'string=) :prefix)
                     ((member type '("xf" "yf") :test #'string=) :postfix)
                     (t :infix))))
    (setf (gethash name *ops*)
          (remove kind (gethash name *ops*) :key #'first))
    (when (plusp prio)
      (push (list kind prio type) (gethash name *ops*)))))

(defun reset-ops ()
  (clrhash *ops*)
  (dolist (o '((1200 "xfx" ":-" "-->" "=>") (1200 "fx" ":-" "?-")
               (1100 "xfy" ";" "|") (1105 "xfy" "|") (1050 "xfy" "->" "*->")
               (1000 "xfy" ",") (990 "xfx" ":=") (900 "fy" "\\+")
               (700 "xfx" "=" "\\=" "==" "\\==" "@<" "@>" "@=<" "@>=" "=.." "is"
                    "=:=" "=\\=" "<" ">" "=<" ">=" ">:<" ":<" "as")
               (600 "xfy" ":") (500 "yfx" "+" "-" "/\\" "\\/" "xor")
               (400 "yfx" "*" "/" "//" "mod" "rdiv" "<<" ">>" "div" "rem" "divmod")
               (200 "xfx" "**") (200 "xfy" "^") (200 "fy" "-" "+" "\\")
               (100 "yfx" ".") (1 "fx" "$")
               (1150 "fx" "dynamic" "discontiguous" "initialization" "meta_predicate"
                     "module_transparent" "multifile" "public" "thread_local" "table")))
    (dolist (name (cddr o)) (add-op (first o) (second o) name))))

(defun op-def (name kind) (find kind (gethash name *ops*) :key #'first))

;;; ------------------------------------------------------------------ lexer

(defstruct (tok (:constructor mk-tok (type val layout))) type val layout)

(defparameter +symch+ "+-*/\\^<>=~:.?@#&$")
(defun symch-p (c) (and c (find c +symch+)))
(defun alnum-p (c) (and c (or (alphanumericp c) (char= c #\_))))

(defun lex-clause (text pos)
  "Tokens of the next clause of TEXT starting at POS, up to and including the
   :end token.  Returns (values tokens new-pos), or NIL at end of input."
  (let ((n (length text)) (toks nil) (layout nil))
    (labels ((peekc (&optional (k 0)) (let ((i (+ pos k))) (and (< i n) (char text i))))
             (emit (type val) (push (mk-tok type val layout) toks) (setf layout nil))
             (read-quoted (q)
               (incf pos)
               (let ((out (make-string-output-stream)))
                 (loop
                   (let ((c (peekc)))
                     (cond ((null c) (error "unterminated quoted item"))
                           ((char= c q)
                            (if (eql (peekc 1) q)
                                (progn (write-char q out) (incf pos 2))
                                (progn (incf pos) (return))))
                           ((char= c #\\)
                            (let ((d (peekc 1)))
                              (incf pos 2)
                              (case d
                                (#\n (write-char #\Newline out))
                                (#\t (write-char #\Tab out))
                                (#\Newline nil)
                                (t (write-char d out)))))
                           (t (write-char c out) (incf pos)))))
                 (get-output-stream-string out))))
      (loop
        (let ((c (peekc)))
          (cond
            ((null c) (return (if toks (error "clause not terminated by '.'") nil)))
            ((member c '(#\Space #\Tab #\Newline #\Return #\Page)) (incf pos) (setf layout t))
            ((char= c #\%) (loop while (and (peekc) (char/= (peekc) #\Newline)) do (incf pos)) (setf layout t))
            ((and (char= c #\/) (eql (peekc 1) #\*))
             (let ((e (search "*/" text :start2 (+ pos 2))))
               (unless e (error "unterminated block comment"))
               (setf pos (+ e 2) layout t)))
            ((digit-char-p c)
             (cond
               ((and (char= c #\0) (eql (peekc 1) #\'))
                (let ((d (peekc 2)))
                  (if (and (eql d #\') (eql (peekc 3) #\'))
                      (progn (emit :int (char-code #\')) (incf pos 4))
                      (progn (emit :int (char-code d)) (incf pos 3)))))
               ((and (char= c #\0) (eql (peekc 1) #\x))
                (let ((s (+ pos 2)) (e (+ pos 2)))
                  (loop while (and (< e n) (digit-char-p (char text e) 16)) do (incf e))
                  (emit :int (parse-integer text :start s :end e :radix 16)) (setf pos e)))
               (t
                (let ((s pos) (e pos) (float nil))
                  (loop while (and (< e n) (or (digit-char-p (char text e)) (char= (char text e) #\_))) do (incf e))
                  (when (and (< (1+ e) n) (char= (char text e) #\.) (digit-char-p (char text (1+ e))))
                    (setf float t) (incf e)
                    (loop while (and (< e n) (digit-char-p (char text e))) do (incf e)))
                  (when (and (< e n) (char-equal (char text e) #\e)
                             (or (and (< (1+ e) n) (digit-char-p (char text (1+ e))))
                                 (and (< (+ e 2) n) (find (char text (1+ e)) "+-") (digit-char-p (char text (+ e 2))))))
                    (setf float t) (incf e 2)
                    (loop while (and (< e n) (digit-char-p (char text e))) do (incf e)))
                  (let ((str (remove #\_ (subseq text s e))))
                    (if float
                        (emit :float (let ((*read-default-float-format* 'double-float))
                                       (coerce (read-from-string str) 'double-float)))
                        (emit :int (parse-integer str))))
                  (setf pos e)))))
            ((or (upper-case-p c) (char= c #\_))
             (let ((s pos)) (loop while (alnum-p (peekc)) do (incf pos)) (emit :var (subseq text s pos))))
            ((alpha-char-p c)
             (let ((s pos)) (loop while (alnum-p (peekc)) do (incf pos)) (emit :atom (subseq text s pos))))
            ((char= c #\') (emit :qatom (read-quoted #\')))
            ((char= c #\") (emit :str (read-quoted #\")))
            ((char= c #\`) (emit :str (read-quoted #\`)))
            ((find c "()[]{},|")
             (incf pos)
             (emit :punct (string c)))
            ((find c "!;") (incf pos) (emit :atom (string c)))
            ((symch-p c)
             (let ((s pos))
               (loop while (symch-p (peekc)) do (incf pos))
               (let ((name (subseq text s pos)))
                 (if (and (string= name ".")
                          (or (null (peekc)) (member (peekc) '(#\Space #\Tab #\Newline #\Return #\%))))
                     (progn (emit :end nil) (return (values (nreverse toks) pos)))
                     (emit :atom name)))))
            (t (error "unexpected character ~S" c))))))))

;;; ------------------------------------------------------------------ parser
;;; AST: (:var name) (:atom name quoted) (:int n) (:float x) (:str s)
;;;      (:cmp name arg...) (:list head tail)  ; [] is (:atom "[]" nil)

(defvar *toks*)
(defun peek-tok () (car *toks*))
(defun next-tok () (pop *toks*))
(defun punct-p (tok s) (and tok (eq (tok-type tok) :punct) (string= (tok-val tok) s)))
(defun expect (s)
  (let ((tk (next-tok)))
    (unless (punct-p tk s) (error "expected ~A, got ~S" s (and tk (tok-val tk))))))

(defun term-start-p (tk)
  "Can TK begin a term (as operand of a prefix operator)?"
  (and tk
       (case (tok-type tk)
         ((:var :int :float :str :qatom) t)
         (:atom t)
         (:punct (member (tok-val tk) '("(" "[" "{") :test #'string=))
         (t nil))))

(defun infix-name (tk)
  "Name if TK can act as an infix operator token, else NIL."
  (and tk
       (case (tok-type tk)
         (:atom (and (op-def (tok-val tk) :infix) (tok-val tk)))
         (:punct (cond ((string= (tok-val tk) ",") ",")
                       ((string= (tok-val tk) "|") "|")))
         (t nil))))

(defun parse (maxprec)
  (multiple-value-bind (left lp) (parse-primary maxprec)
    (loop
      (let* ((tk (peek-tok)) (name (infix-name tk)))
        (unless name (return))
        (let* ((def (op-def name :infix)) (def (or def (op-def "|" :infix))))
          (destructuring-bind (kind p type) def
            (declare (ignore kind))
            (let ((lmax (if (string= type "yfx") p (1- p)))
                  (rmax (if (string= type "xfy") p (1- p))))
              (when (or (> p maxprec) (> lp lmax)) (return))
              (next-tok)
              (let ((right (parse rmax)))
                (setf left (list :cmp (if (string= name "|") ";" name) left right)
                      lp p)))))))
    (values left lp)))

(defun parse-args ()
  (let ((args (list (parse 999))))
    (loop while (punct-p (peek-tok) ",") do (next-tok) (push (parse 999) args))
    (expect ")")
    (nreverse args)))

(defun parse-list ()
  (if (punct-p (peek-tok) "]")
      (progn (next-tok) '(:atom "[]" nil))
      (let ((items (list (parse 999))) (tail '(:atom "[]" nil)))
        (loop while (punct-p (peek-tok) ",") do (next-tok) (push (parse 999) items))
        (when (punct-p (peek-tok) "|") (next-tok) (setf tail (parse 999)))
        (expect "]")
        (let ((r tail)) (dolist (i items) (setf r (list :list i r))) r))))

(defun parse-primary (maxprec)
  (let ((tk (next-tok)))
    (unless tk (error "unexpected end of clause"))
    (ecase (tok-type tk)
      (:int (values (list :int (tok-val tk)) 0))
      (:float (values (list :float (tok-val tk)) 0))
      (:str (values (list :str (tok-val tk)) 0))
      (:var (values (list :var (tok-val tk)) 0))
      (:punct
       (let ((s (tok-val tk)))
         (cond ((string= s "(") (let ((tm (parse 1200))) (expect ")") (values tm 0)))
               ((string= s "[") (values (parse-list) 0))
               ((string= s "{") (if (punct-p (peek-tok) "}")
                                    (progn (next-tok) (values '(:atom "{}" nil) 0))
                                    (let ((tm (parse 1200))) (expect "}") (values (list :cmp "{}" tm) 0))))
               (t (error "unexpected ~S" s)))))
      ((:atom :qatom)
       (let* ((name (tok-val tk)) (quoted (eq (tok-type tk) :qatom)) (nxt (peek-tok)))
         (cond
           ;; functional notation: name(
           ((and nxt (punct-p nxt "(") (not (tok-layout nxt)))
            (next-tok)
            (values (list* :cmp name (parse-args)) 0))
           ;; negative number literal
           ((and (not quoted) (member name '("-" "+") :test #'string=) nxt
                 (member (tok-type nxt) '(:int :float)) (not (tok-layout nxt)))
            (next-tok)
            (values (list (tok-type nxt) (if (string= name "-") (- (tok-val nxt)) (tok-val nxt))) 0))
           ;; prefix operator
           ((and (not quoted) (op-def name :prefix))
            (destructuring-bind (kind p type) (op-def name :prefix)
              (declare (ignore kind))
              (let ((as-atom (or (not (term-start-p nxt))
                                 ;; `- = x`: next is an infix operator that cannot start a term
                                 (and (eq (tok-type nxt) :atom) (infix-name nxt)
                                      (not (op-def (tok-val nxt) :prefix))
                                      (not (punct-p (cadr *toks*) "("))))))
                (if as-atom
                    (values (list :atom name nil) (if (> p maxprec) 0 p))
                    (let* ((p (if (> p maxprec) 999 p))
                           (argmax (if (string= type "fy") p (1- p)))
                           (arg (parse argmax)))
                      (values (list :cmp name arg) p))))))
           (t (values (list :atom name quoted) 0))))))))

(defun parse-clause-tokens (tokens)
  (let ((*toks* tokens))
    (let ((tm (parse 1200)))
      (unless (eq (tok-type (peek-tok)) :end)
        (error "trailing input after term: ~S" (tok-val (peek-tok))))
      tm)))


;;; ------------------------------------------------------------------ DCG

(defvar *dcg-counter* 0)
(defun dcg-var () (list :var (format nil "_dcg_~D" (incf *dcg-counter*))))
(defun mk-conj (a b) (list :cmp "," a b))
(defun mk-unify (a b) (list :cmp "=" a b))
(defun ast-list (items tail)
  (let ((r tail)) (dolist (i (reverse items) r) (setf r (list :list i r)))))

(defun dcg-body (b s0 s)
  "AST goal for grammar body B threaded from S0 to S."
  (cond
    ((eq (first b) :var) (list :cmp "phrase" b s0 s))
    ((ctl-p b "," 2)
     (let ((m (dcg-var)))
       (mk-conj (dcg-body (third b) s0 m) (dcg-body (fourth b) m s))))
    ((or (ctl-p b ";" 2))
     (list :cmp ";" (dcg-body (third b) s0 s) (dcg-body (fourth b) s0 s)))
    ((ctl-p b "->" 2)
     (let ((m (dcg-var)))
       (list :cmp "->" (dcg-body (third b) s0 m) (dcg-body (fourth b) m s))))
    ((ctl-p b "\\+" 1)
     (mk-conj (list :cmp "\\+" (dcg-body (third b) s0 (dcg-var))) (mk-unify s0 s)))
    ((ctl-p b "{}" 1) (mk-conj (third b) (mk-unify s0 s)))
    ((and (eq (first b) :atom) (string= (second b) "!")) (mk-conj b (mk-unify s0 s)))
    ((and (eq (first b) :atom) (string= (second b) "[]")) (mk-unify s0 s))
    ((eq (first b) :list)
     (let ((items nil) (x b))
       (loop while (eq (first x) :list) do (push (second x) items) (setf x (third x)))
       (mk-unify s0 (ast-list (nreverse items) s))))
    ((ctl-p b "call" (- (length b) 2)) (append b (list s0 s)))
    ((eq (first b) :atom) (list :cmp (second b) s0 s))
    ((eq (first b) :cmp) (append b (list s0 s)))
    (t (error "bad DCG body ~S" b))))

(defun dcg-rule (head body)
  (let ((s0 (dcg-var)) (s (dcg-var)))
    (list :cmp ":-"
          (if (eq (first head) :atom) (list :cmp (second head) s0 s) (append head (list s0 s)))
          (dcg-body body s0 s))))

;;; ------------------------------------------------------------------ emission

(defvar *qp-mode* nil)
(defvar *varmap*)          ; Prolog name -> Lisp symbol, per clause
(defvar *used*)            ; upcased names already taken

(defun lisp-var (name)
  (if (string= name "_")
      (intern "_" :cl-user)
      (or (gethash name *varmap*)
          (setf (gethash name *varmap*)
                (let* ((base (string-upcase name)) (cand base) (k 1))
                  (loop while (gethash cand *used*) do (setf cand (format nil "~A~~~D" base (incf k))))
                  (setf (gethash cand *used*) t)
                  (intern (concatenate 'string "?" cand) :cl-user))))))

(defun lisp-atom (name quoted)
  (cond ((string= name "[]") nil)
        ;; the engine reads every symbol starting with ? as a variable, so an atom
        ;; like `?` (chat_parser's end-of-sentence marker) is renamed consistently
        ((and (plusp (length name)) (char= (char name 0) #\?))
         (intern (concatenate 'string "$q" name) :cl-user))
        ((and (not quoted) (string= name "nil")) (intern "nil" :cl-user)) ; not the empty list
        ;; qprolog mode: a quoted atom without upper-case letters is the same atom as the
        ;; unquoted one (which the reader folds), so fold it; 'Foo' keeps its case.
        ((and quoted *qp-mode* (notany #'upper-case-p name)) (intern (string-upcase name) :cl-user))
        (quoted (if (string= name (string-upcase name)) (intern name :cl-user) (intern name :cl-user)))
        (t (intern (string-upcase name) :cl-user))))

(defun sym (s) (intern (string-upcase s) :cl-user))

(defun data (tm)
  "Term as engine data."
  (ecase (first tm)
    (:var (lisp-var (second tm)))
    (:atom (lisp-atom (second tm) (third tm)))
    (:int (second tm))
    (:float (second tm))
    (:str (second tm))
    (:list (list-data tm))
    (:cmp (cons (lisp-atom (second tm) nil) (mapcar #'data (cddr tm))))))

;;; qprolog mode: a proper Prolog list whose first element is an atom, such as
;;; [a,b,c], would print as (a b c), which is also the compound a(b,c).  The
;;; lispy engine cannot tell them apart; qprolog can, provided such a list is
;;; written (:l a b c).  Only this ambiguous shape is marked; partial lists
;;; (a b . ?t), lists that start with a variable, number, list or compound, and
;;; [] are unambiguous and unchanged.

(defun var-symbol-p (x)
  (and (symbolp x) x (plusp (length (symbol-name x)))
       (or (char= (char (symbol-name x) 0) #\?) (string= (symbol-name x) "_"))))

(defun list-data (tm)
  (let ((elems nil) (tail tm))
    (loop while (eq (first tail) :list)
          do (push (data (second tail)) elems) (setf tail (third tail)))
    (setf elems (nreverse elems))
    (let* ((tl (data tail)) (l (append elems tl)))
      (cond ((and *qp-mode* (consp tl))          ; compound tail: (:l e1 .. en :tail T)
             (list* :l (append elems (list :tail tl))))
            ((and *qp-mode* (null tl) (car l) (symbolp (car l)) (not (var-symbol-p (car l))))
             (cons :l l))
            (t l)))))

(defparameter *arith-ops*
  '("+" "-" "*" "/" "//" "mod" "rem" "div" "min" "max" "abs" "sign" "gcd" "**" "^" ">>" "<<"
    "/\\" "\\/" "xor" "\\" "sqrt" "exp" "log" "sin" "cos" "tan" "atan" "atan2" "float" "integer"
    "round" "truncate" "floor" "ceiling" "random"))

(defun expr (tm)
  "Arithmetic expression: evaluable compounds become prefix forms."
  (case (first tm)
    (:cmp (if (member (second tm) *arith-ops* :test #'string=)
              (cons (sym (string-upcase (second tm))) (mapcar #'expr (cddr tm)))
              (data tm)))
    (t (data tm))))

(defun conj-list (tm)
  (if (and (eq (first tm) :cmp) (string= (second tm) ",") (= (length tm) 4))
      (append (conj-list (third tm)) (conj-list (fourth tm)))
      (list tm)))

(defun ctl-p (tm name arity)
  (and (eq (first tm) :cmp) (string= (second tm) name) (= (length tm) (+ 2 arity))))

(defun conj-form (tm)
  "One goal or (:and g...)."
  (let ((gs (mapcar #'goal (conj-list tm))))
    (if (cdr gs) (cons :and gs) (car gs))))

(defun arm (tm)
  (if (ctl-p tm "->" 2)
      (list (conj-form (third tm)) (sym "->") (conj-form (fourth tm)))
      (list (conj-form tm))))

(defun or-form (tm)
  "TM is a `;`, `->` or `*->` term: (:or arm...) with flat arms."
  (let ((arms nil))
    (loop
      (cond ((ctl-p tm ";" 2) (setf arms (append arms (arm (third tm)))) (setf tm (fourth tm)))
            (t (setf arms (append arms (arm tm))) (return))))
    (cons :or arms)))

(defun meta (tm)
  "A term used as a goal argument (findall's goal, \\+'s goal ...)."
  (cond ((or (ctl-p tm "," 2) (ctl-p tm ";" 2) (ctl-p tm "->" 2))
         (if (ctl-p tm "," 2) (list :or (conj-form tm)) (or-form tm)))
        (t (goal tm))))

(defparameter *cmp-map*
  '(("=:=" . "=") ("=\\=" . "/=") ("<" . "<") (">" . ">") ("=<" . "<=") (">=" . ">=")))

(defun goal (tm)
  (case (first tm)
    (:var (list (sym "call") (data tm)))
    (:atom (let ((n (second tm)))
             (cond ((member n '("true" "!") :test #'string=) (sym (string-upcase n)))
                   ((member n '("fail" "false") :test #'string=) (sym "fail"))
                   ((string= n "$") (sym "!"))
                   (t (list (lisp-atom n nil))))))
    (:cmp
     (let ((name (second tm)) (args (cddr tm)))
       (cond
         ((and (string= name ",") (= (length args) 2)) (conj-form tm)) ; only reached nested
         ((and (member name '(";" "->" "*->") :test #'string=) (= (length args) 2)) (or-form tm))
         ((and (string= name "=") (= (length args) 2)) (list (sym "unify") (data (first args)) (data (second args))))
         ((and (string= name "is") (= (length args) 2)) (list (sym "is") (data (first args)) (expr (second args))))
         ((and (assoc name *cmp-map* :test #'string=) (= (length args) 2))
          (list (sym (cdr (assoc name *cmp-map* :test #'string=))) (expr (first args)) (expr (second args))))
         ((and (string= name "$") (= (length args) 1)) (goal (first args)))
         ((and (member name '("\\+" "once" "ignore" "not") :test #'string=) (= (length args) 1))
          (list (lisp-atom name nil) (meta (first args))))
         ((and (string= name "call") (>= (length args) 1))
          (list* (sym "call") (meta (first args)) (mapcar #'data (rest args))))
         ((and (member name '("findall" "aggregate_all" "bagof" "setof") :test #'string=) (>= (length args) 3))
          (list* (lisp-atom name nil) (data (first args)) (meta (second args)) (mapcar #'data (cddr args))))
         ((and (string= name "forall") (= (length args) 2))
          (list (sym "forall") (meta (first args)) (meta (second args))))
         (t (cons (lisp-atom name nil) (mapcar #'data args))))))
    (t (error "not callable: ~S" tm))))

(defun body-goals (tm) (mapcar #'goal (conj-list tm)))

(defun pi-specs (tm)
  "Predicate indicators in a dynamic/discontiguous directive argument."
  (cond ((or (ctl-p tm "," 2)) (append (pi-specs (third tm)) (pi-specs (fourth tm))))
        ((eq (first tm) :list) (cons (second tm) (pi-specs (third tm))))
        ((eq (first tm) :atom) nil)
        (t (list tm))))

(defun emit-clause (tm out)
  (let ((*varmap* (make-hash-table :test 'equal)) (*used* (make-hash-table :test 'equal))
        (*package* (find-package :cl-user)) (*print-pretty* t) (*print-right-margin* 100)
        (*print-case* :downcase) (*print-circle* nil)
        (form nil))
    (flet ((head (h) (if (eq (first h) :atom) (list (lisp-atom (second h) nil)) (data h))))
      (setf form
            (cond
              ((ctl-p tm ":-" 1)
               (let ((d (third tm)))
                 (cond
                   ((and (eq (first d) :cmp) (member (second d) '("dynamic" "discontiguous" "multifile") :test #'string=))
                    (if (string= (second d) "dynamic")
                        (cons 'progn
                              (loop for spec in (pi-specs (third d))
                                    collect (list (sym "declare-dynamic")
                                                  (list 'quote (data spec)))))
                        nil))
                   ((and (eq (first d) :cmp) (member (second d) '("use_module" "ensure_loaded" "set_prolog_flag" "style_check"
                                                                  "module" "initialization" "op" "license")
                                                     :test #'string=))
                    nil)
                   (t (error "unsupported directive ~S" d)))))
              ((ctl-p tm ":-" 2)
               (list* (sym "<-") (head (third tm)) (body-goals (fourth tm))))
              ((ctl-p tm "=>" 2)
               (list* (sym "<-") (head (third tm)) (sym "!") (body-goals (fourth tm))))
              ((ctl-p tm "-->" 2) (return-from emit-clause (emit-clause (dcg-rule (third tm) (fourth tm)) out)))
              (t (list (sym "<-") (head tm)))))
      (when form
        (let ((text (prin1-to-string form)))
          (write-string (tidy text) out) (terpri out))))))

(defun data-spec (x) x)

(defun tidy (text)
  "Print the negation symbol as \\+ rather than |\\\\+|."
  (let ((bar (format nil "|~A~A~A|" #\\ #\\ #\+)))
    (loop for pos = (search bar text) while pos
          do (setf text (concatenate 'string (subseq text 0 pos)
                                     (format nil "~A~A~A" #\\ #\\ #\+)
                                     (subseq text (+ pos (length bar))))))
    text))

;;; ------------------------------------------------------------------ driver

(defun apply-op-directive (tm)
  (when (ctl-p tm ":-" 1)
    (let ((d (third tm)))
      (when (and (eq (first d) :cmp) (string= (second d) "op") (= (length d) 5))
        (let ((names (let ((n (fifth d)))
                       (if (member (first n) '(:list)) (mapcar #'second (list-items n)) (list (second n))))))
          (dolist (nm names) (add-op (second (third d)) (second (fourth d)) nm)))))))

(defun list-items (l) (if (eq (first l) :list) (cons (second l) (list-items (third l))) nil))

(defun translate-text (text out &key (name "program"))
  (reset-ops)
  (let ((pos 0) (count 0))
    (format out ";;;; ~A.lisp -- GENERATED from swi/~A.pl by bench/pl2lispy.lisp; do not edit.~%~%" name name)
    (loop
      (multiple-value-bind (toks npos) (lex-clause text pos)
        (unless toks (return))
        (setf pos npos)
        (let ((tm (handler-case (parse-clause-tokens toks)
                    (error (e) (error "~A: parse error near ~S: ~A" name
                                      (mapcar #'tok-val (subseq toks 0 (min 12 (length toks)))) e)))))
          (apply-op-directive tm)
          (handler-case (emit-clause tm out)
            (error (e) (error "~A: cannot translate clause starting ~S: ~A" name
                              (mapcar #'tok-val (subseq toks 0 (min 12 (length toks)))) e)))
          (incf count))))
    count))

(defun slurp (path)
  (with-open-file (in path :external-format :utf-8)
    (let ((s (make-string (file-length in))))
      (subseq s 0 (read-sequence s in)))))

(defun translate-file (in-path out-path)
  (let ((name (pathname-name in-path)))
    (with-open-file (out out-path :direction :output :if-exists :supersede :external-format :utf-8)
      (translate-text (slurp in-path) out :name name))))

(defun translate-all (in-dir out-dir &optional names)
  (ensure-directories-exist out-dir)
  (dolist (in (directory (merge-pathnames "*.pl" in-dir)))
    (let ((n (pathname-name in)))
      (unless (member n '("run" "programs" "swi" "swi-bench") :test #'string=)
        (when (or (null names) (member n names :test #'string=))
          (format t "~A: ~D clauses~%" n
                  (translate-file in (merge-pathnames (format nil "~A.lisp" n) out-dir))))))))

;;; ---- queries -------------------------------------------------------------
(defun tm-var-names (tm &optional acc)
  "Named variables of a parsed term, first-occurrence order (reversed accumulator)."
  (case (first tm)
    (:var (if (or (string= (second tm) "_") (member (second tm) acc :test #'string=)) acc (cons (second tm) acc)))
    (:list (tm-var-names (third tm) (tm-var-names (second tm) acc)))
    (:cmp (let ((a acc)) (dolist (x (cddr tm) a) (setf a (tm-var-names x a)))))
    (t acc)))

(defun translate-query (text &key qp)
  "Prolog query text (no final dot) -> (values goal-text var-symbol-names) where
goal-text is the lispy/qprolog goal form printed as text and var-symbol-names are the
symbol names (e.g. \"?X\") of the query's named variables in first-occurrence order."
  (reset-ops)
  (let ((*qp-mode* qp))
    (multiple-value-bind (toks npos) (lex-clause (concatenate 'string text " .") 0)
      (declare (ignore npos))
      (let* ((tm (parse-clause-tokens toks))
             (*varmap* (make-hash-table :test 'equal)) (*used* (make-hash-table :test 'equal))
             (*package* (find-package :cl-user)) (*print-pretty* nil) (*print-case* :downcase)
             (names (reverse (tm-var-names tm)))
             (form (conj-form tm))
             (syms (mapcar (lambda (n) (symbol-name (lisp-var n))) names)))
        (values (prin1-to-string form) syms)))))
