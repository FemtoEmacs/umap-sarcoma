;;;; edinburgh-reader.lisp -- a classic-textual-Prolog front end for
;;;; claude-prolog, 2026-09-14. Load AFTER prolog-engine.lisp.
;;;;
;;;; WHAT THIS IS: a tokenizer plus a small recursive-descent parser that
;;;; reads ordinary Prolog source text (facts, rules, directives, queries
;;;; written the way any Prolog textbook writes them) and turns it into
;;;; exactly the same raw term shapes the existing bracket syntax already
;;;; produces -- plain Lisp lists, ?-prefixed symbols for named variables,
;;;; the bare symbol _ for the anonymous variable -- then hands them
;;;; straight to ADD-CLAUSE / RUN-QUERY. Nothing in prolog-engine.lisp
;;;; changes because of this file (a separate, tiny, well-justified fix to
;;;; the arithmetic-comparison builtins is documented in NOTES.md and
;;;; landed in prolog-engine.lisp itself, not here); this is purely a
;;;; front end sitting in front of the same engine.
;;;;
;;;; WHY THERE IS NO OPERATOR TABLE HERE, AT ALL -- this is the single
;;;; decision that makes everything else in this file simple, so it's
;;;; worth stating plainly before the code: classic Prolog needs a real
;;;; operator-precedence parser (xfx/xfy/yfx priorities, user-definable
;;;; via op/3) ONLY because arithmetic needs `2+3*4` to parse as
;;;; +(2,*(3,4)), not *(+(2,3),4) -- multi-level precedence exists
;;;; entirely to serve infix arithmetic. This project already has a
;;;; perfectly good arithmetic evaluator (LISP-EVAL / EVAL-PROLOG-FORM,
;;;; unchanged), so arithmetic in THIS syntax is never written infix in
;;;; the first place -- it's written as an ordinary compound term
;;;; (+(X,1)), which needs no precedence at all (comma-delimited argument
;;;; lists are already fully unambiguous), or as a literal embedded Lisp
;;;; form ((+ X 1)), which needs no precedence either (parenthesized
;;;; prefix notation is unambiguous by construction -- that's what Lisp's
;;;; own reader has always relied on). With arithmetic out of the
;;;; picture, nothing else in Prolog's grammar ever needed multi-level
;;;; precedence to begin with: `:-` (the rule neck), `,` (body-goal
;;;; separator), and `!` (cut) are each a single, fixed-position rule a
;;;; plain recursive-descent reader already handles directly, with no
;;;; operator machinery backing them. So READ-TERM below has no "now
;;;; check for a following infix operator" loop at all -- it dispatches
;;;; once on the current token and returns.
;;;;
;;;; THE TWO PARENTHESIS FORMS, disambiguated for free: `foo(X, Y)` is a
;;;; compound term (ISO's own lexical rule: the '(' must sit tight
;;;; against the functor, no layout text between them -- `foo (X)` is NOT
;;;; a compound term in real Prolog either). `(+ X 1)` -- a bare '(' in
;;;; term-starting position, not immediately following an atom -- used
;;;; to mean "grouping parens for operator precedence"; since there are
;;;; no infix operators left to disambiguate, that shape has no
;;;; grammatical job anymore, so it's repurposed here as "read a literal
;;;; Lisp-shaped expression" (space-separated, not comma-separated) --
;;;; the exact same recursive "read terms until the matching close-paren"
;;;; loop as a compound term's argument list, just entered through a
;;;; different door and separated by whitespace instead of comma.
;;;;
;;;; ...OR RATHER -- once that shape means "this is Lisp", the contents
;;;; should just BE read as Lisp, full stop, rather than re-tokenized by
;;;; this file's own Prolog-only character classes. Concretely: those
;;;; classes don't allow the hyphens that are all over this codebase's
;;;; own names (LISP-EVAL chief among them -- every existing call from
;;;; inside one of these forms references a hyphenated Lisp name), and
;;;; rather than growing a second, hyphen-aware identifier table just for
;;;; this one context, READ-LISP-FORM-TAIL hands the raw text straight to
;;;; CL:READ (case-preserved, so an upper-case-led symbol can still be
;;;; told apart from a lower-case-led one after the fact) and translates
;;;; the symbols it hands back using the exact same two rules READ-TERM
;;;; uses everywhere else -- upper-case/underscore-led becomes a ?-
;;;; prefixed variable, everything else becomes an upcased atom. This is
;;;; the same "leave to Lisp everything Lisp does well" principle this
;;;; whole design already rests on, just applied one level deeper: Lisp's
;;;; own reader already knows how to tokenize Lisp, hyphens included.
;;;;
;;;; SURFACE SYMBOLS THAT GET REWRITTEN AT GOAL POSITION ONLY (never for
;;;; a nested/data occurrence of the same functor): plain `=` means
;;;; unification in every Prolog dialect, but this engine's own internal
;;;; BUILTIN-STEP case named `=` is Lisp numeric equality (a pre-existing,
;;;; harmless-until-now naming collision: nothing before this file ever
;;;; wrote `=` as a bare goal, everything went through LISP-EVAL, which
;;;; evaluates before that case is ever reached). So READ-GOAL rewrites a
;;;; goal-position `=(A,B)` to `unify(A,B)` -- the engine's real
;;;; unification builtin -- rather than touching prolog-engine.lisp's
;;;; existing `=` case, which stays exactly as it was; `=:=` (ISO
;;;; arithmetic equality) maps onto that unchanged internal `=` instead.
;;;; Full table: `=` -> UNIFY, `=:=` -> internal `=`, `=\=` -> internal
;;;; `/=`, `=<` -> internal `<=`; `<`, `>`, `>=` need no translation, same
;;;; spelling both places. NOT implemented, matching \+/1's own
;;;; not-yet-built status in NOTES.md's roadmap: `\=` (not unifiable),
;;;; `==`/`\==` (structural equality) -- these read as ordinary compound-
;;;; term goals and simply FAIL at runtime (no clauses exist for them),
;;;; which is honest, not silently wrong, just incomplete.
;;;;
;;;; NEGATIVE NUMBERS NEED NO SPECIAL DISAMBIGUATION RULE, as a
;;;; consequence of the same operator-free design, not a separate
;;;; decision: with no prefix-operator-application grammar left at all,
;;;; a bare `-5` (tight, no parens) has exactly ONE possible parse --
;;;; there is no OTHER production that could consume that character
;;;; sequence -- so it is unambiguously a negative number literal. `- 5`
;;;; (a space, no parens) is the atom `-` followed by the number `5`,
;;;; two complete terms in a row with nothing legally connecting them --
;;;; which is exactly the kind of thing this file's fixed small
;;;; "after one complete term, only , ) ] | or . may follow" rule
;;;; catches automatically, as a syntax error, not a silent misparse.
;;;;
;;;; CASE CONVENTIONS: plain (unquoted) atoms are upcased on intern, to
;;;; interoperate with the existing bracket syntax, where CL's own reader
;;;; already upcases everything by default -- `color(apple, red)` here
;;;; and `(<- (color apple red))` there refer to the identical interned
;;;; symbols. A QUOTED atom ('Apple') preserves its case exactly as
;;;; written -- quoting exists precisely to let an atom mean something a
;;;; bare identifier can't spell, and forcing it through the same
;;;; upcasing would defeat that. Variable names are never case-folded at
;;;; all (Foo and FOO are genuinely different variables, matching ISO).

;; ---------------------------------------------------------------------------
;; Position-tracked source buffer and the one error condition this file
;; signals -- a single, minimal type (not a hierarchy, matching the rest
;; of this codebase's plain (error "...") style) so the consult loop below
;; can specifically catch "a syntax error I know how to resync past"
;; without also swallowing an unrelated bug.
;; ---------------------------------------------------------------------------

(define-condition edinburgh-syntax-error (error)
  ((text :initarg :text :reader edinburgh-syntax-error-text))
  (:report (lambda (c stream) (write-string (edinburgh-syntax-error-text c) stream))))

(defstruct pstream
  text (pos 0) (line 1) (col 1) source-name (lookahead nil))

(defun ps-make (text &optional (source-name "<string>"))
  (make-pstream :text text :source-name source-name))

(defun ps-eof-p (ps) (>= (pstream-pos ps) (length (pstream-text ps))))

(defun ps-peek (ps &optional (ahead 0))
  "Raw character AHEAD positions past the current read position, with NO
   layout-skipping and no token buffering -- used only for the small set
   of one-character lookahead decisions (is this '-' glued to a digit? is
   this '.' glued to layout?) that have to happen below the token level."
  (let ((i (+ (pstream-pos ps) ahead)))
    (if (< i (length (pstream-text ps))) (char (pstream-text ps) i) nil)))

(defun ps-advance (ps)
  (let ((ch (ps-peek ps)))
    (when ch
      (incf (pstream-pos ps))
      (if (char= ch #\Newline)
          (progn (incf (pstream-line ps)) (setf (pstream-col ps) 1))
          (incf (pstream-col ps))))
    ch))

(defun ps-error (ps fmt &rest args)
  (error 'edinburgh-syntax-error
         :text (format nil "~A:~D:~D: ~A" (pstream-source-name ps)
                        (pstream-line ps) (pstream-col ps)
                        (apply #'format nil fmt args))))

;; ---------------------------------------------------------------------------
;; Layout: whitespace, %-line comments, /* ... */ block comments. Skipped
;; as a unit before every token -- none of it is ever visible to the
;; tokenizer proper.
;; ---------------------------------------------------------------------------

(defun ps-skip-layout (ps)
  (loop
    (let ((ch (ps-peek ps)))
      (cond
        ((null ch) (return))
        ((member ch '(#\Space #\Tab #\Newline #\Return #\Linefeed #\Page))
         (ps-advance ps))
        ((char= ch #\%)
         (loop until (or (ps-eof-p ps) (char= (ps-peek ps) #\Newline))
               do (ps-advance ps)))
        ((and (char= ch #\/) (eql (ps-peek ps 1) #\*))
         (let ((start-line (pstream-line ps)) (start-col (pstream-col ps)))
           (ps-advance ps) (ps-advance ps)
           (loop
             (when (ps-eof-p ps)
               (ps-error ps "unterminated /* comment opened at line ~D col ~D"
                         start-line start-col))
             (if (and (char= (ps-peek ps) #\*) (eql (ps-peek ps 1) #\/))
                 (progn (ps-advance ps) (ps-advance ps) (return))
                 (ps-advance ps)))))
        (t (return))))))

;; ---------------------------------------------------------------------------
;; Character classes.
;; ---------------------------------------------------------------------------

(defparameter *symbol-chars* "+-*/\\^<>=~:.?@#&")
(defparameter *solo-chars* "()[]|,!;")

(defun symbol-char-p (ch) (and ch (find ch *symbol-chars*)))
(defun solo-char-p (ch) (and ch (find ch *solo-chars*)))
(defun ident-start-p (ch) (and ch (alpha-char-p ch)))
(defun ident-char-p (ch) (and ch (or (alphanumericp ch) (char= ch #\_))))
(defun atom-ident-char-p (ch)
  "Like IDENT-CHAR-P but also lets '-' continue an already-started atom
   identifier. This codebase's own predicate/function names are
   hyphenated throughout (list-len, count-up3, register-callable, ...),
   and with no infix operators anywhere in this grammar (see the file
   banner), a hyphen appearing tight inside an identifier can never mean
   anything else -- there is no infix subtraction here at all, tight or
   spaced, for it to be confused with. Deliberately NOT used for
   variable identifiers (PS-SCAN-VARIABLE, below, always passes the
   plain IDENT-CHAR-P): ?X-1 must stay \"variable X\" followed by the
   numeral -1, not one variable literally named \"X-1\"."
  (or (ident-char-p ch) (and ch (char= ch #\-))))
(defun digit-ch-p (ch) (and ch (digit-char-p ch)))

;; ---------------------------------------------------------------------------
;; Tokens.
;; ---------------------------------------------------------------------------

(defstruct tok type value (tight-open-p nil) line col)

(defun describe-tok (tok)
  (case (tok-type tok)
    (:eof "end of input")
    (:dot "end of clause '.'")
    (:open "'('") (:close "')'")
    (:open-list "'['") (:close-list "']'")
    (:bar "'|'") (:comma "','")
    (:atom (format nil "atom ~A" (tok-value tok)))
    (:var (format nil "variable ~A" (tok-value tok)))
    (:number (format nil "number ~A" (tok-value tok)))
    (:string (format nil "string ~S" (tok-value tok)))
    (t (format nil "~A" (tok-type tok)))))

(defun ps-peek-token (ps)
  (or (pstream-lookahead ps)
      (setf (pstream-lookahead ps) (ps-scan-token ps))))

(defun ps-next-token (ps)
  (let ((tok (ps-peek-token ps)))
    (setf (pstream-lookahead ps) nil)
    tok))

(defun intern-upcased (text) (intern (string-upcase text)))

(defun ps-scan-token (ps)
  (ps-skip-layout ps)
  (let ((line (pstream-line ps)) (col (pstream-col ps)))
    (flet ((tk (type &optional value)
             (make-tok :type type :value value :line line :col col
                       :tight-open-p (and (eq type :atom) (eql (ps-peek ps) #\()))))
      (if (ps-eof-p ps)
          (tk :eof)
          (let ((ch (ps-peek ps)))
            (cond
              ((char= ch #\() (ps-advance ps) (tk :open))
              ((char= ch #\)) (ps-advance ps) (tk :close))
              ((char= ch #\[) (ps-advance ps) (tk :open-list))
              ((char= ch #\]) (ps-advance ps) (tk :close-list))
              ((char= ch #\|) (ps-advance ps) (tk :bar))
              ((char= ch #\,) (ps-advance ps) (tk :comma))
              ((char= ch #\!) (ps-advance ps) (tk :atom (intern "!")))
              ((char= ch #\;) (ps-advance ps) (tk :atom (intern-upcased ";")))
              ((char= ch #\.)
               (if (or (null (ps-peek ps 1))
                       (member (ps-peek ps 1) '(#\Space #\Tab #\Newline #\Return #\Linefeed #\% #\Page)))
                   (progn (ps-advance ps) (tk :dot))
                   (ps-scan-symbolic-atom ps line col)))
              ((char= ch #\') (ps-advance ps) (tk :atom (ps-read-quoted ps #\' t)))
              ((char= ch #\") (ps-advance ps) (tk :string (ps-read-quoted ps #\" nil)))
              ((or (digit-ch-p ch)
                   (and (char= ch #\-) (digit-ch-p (ps-peek ps 1))))
               (tk :number (ps-scan-number ps)))
              ((or (upper-case-p ch) (char= ch #\_))
               (tk :var (ps-scan-variable ps)))
              ((and (alpha-char-p ch) (lower-case-p ch))
               (tk :atom (intern-upcased (ps-scan-ident ps #'atom-ident-char-p))))
              ((symbol-char-p ch) (ps-scan-symbolic-atom ps line col))
              (t (ps-error ps "unexpected character ~C" ch))))))))

(defun ps-scan-ident (ps &optional (char-p #'ident-char-p))
  (with-output-to-string (out)
    (loop while (funcall char-p (ps-peek ps)) do (write-char (ps-advance ps) out))))

(defun ps-scan-symbolic-atom (ps line col)
  (let ((text (with-output-to-string (out)
                (loop while (symbol-char-p (ps-peek ps)) do (write-char (ps-advance ps) out)))))
    (make-tok :type :atom :value (intern-upcased text) :line line :col col
              :tight-open-p (eql (ps-peek ps) #\())))

(defun ps-scan-variable (ps)
  (let ((text (ps-scan-ident ps)))
    (if (string= text "_")
        (intern "_")
        (intern (concatenate 'string "?" text)))))

(defun ps-scan-number (ps)
  (let ((start (pstream-pos ps)))
    (when (char= (ps-peek ps) #\-) (ps-advance ps))
    (loop while (digit-ch-p (ps-peek ps)) do (ps-advance ps))
    (when (and (eql (ps-peek ps) #\.) (digit-ch-p (ps-peek ps 1)))
      (ps-advance ps)
      (loop while (digit-ch-p (ps-peek ps)) do (ps-advance ps)))
    (when (and (member (ps-peek ps) '(#\e #\E))
               (or (digit-ch-p (ps-peek ps 1))
                   (and (member (ps-peek ps 1) '(#\+ #\-)) (digit-ch-p (ps-peek ps 2)))))
      (ps-advance ps)
      (when (member (ps-peek ps) '(#\+ #\-)) (ps-advance ps))
      (loop while (digit-ch-p (ps-peek ps)) do (ps-advance ps)))
    (let* ((text (subseq (pstream-text ps) start (pstream-pos ps)))
           (*read-eval* nil)
           (value (read-from-string text)))
      (unless (numberp value) (ps-error ps "malformed number ~A" text))
      value)))

(defun ps-read-quoted (ps close-char atom-p)
  "Read the body of a '...' atom or \"...\" string, ATOM-P distinguishing
   only which escaped form of CLOSE-CHAR is legal (\\' inside an atom,
   \\\" inside a string) -- the opening delimiter is already consumed.
   Supports the common escapes (\\\\ \\n \\t \\' \\\"), not the full ISO
   octal/hex escape grammar -- anything else after a backslash is a clear
   error rather than a silently-wrong pass-through character."
  (let ((start-line (pstream-line ps)) (start-col (pstream-col ps)))
    (let ((text (with-output-to-string (out)
                  (loop
                    (when (ps-eof-p ps)
                      (ps-error ps "unterminated ~:[string~;quoted atom~] opened at line ~D col ~D"
                                atom-p start-line start-col))
                    (let ((ch (ps-advance ps)))
                      (cond
                        ((char= ch close-char) (return))
                        ((char= ch #\\)
                         (let ((esc (ps-advance ps)))
                           (case esc
                             (#\n (write-char #\Newline out))
                             (#\t (write-char #\Tab out))
                             (#\\ (write-char #\\ out))
                             ((#\' #\") (write-char esc out))
                             (t (ps-error ps "unknown escape sequence \\~A" esc)))))
                        (t (write-char ch out))))))))
      (if atom-p (intern text) text))))

;; ---------------------------------------------------------------------------
;; Terms. No operator-precedence loop -- see the file banner for why one
;; complete READ-TERM dispatch IS a whole term here.
;; ---------------------------------------------------------------------------

(defun ps-unread-if-dot (ps tok)
  "If TOK is the clause-terminating '.', put it back into the one-token
   lookahead buffer before signalling a syntax error. Every caller below
   has just consumed TOK via PS-NEXT-TOKEN to find out it doesn't fit the
   grammar there; if TOK happens to be the '.' that was actually ending
   the (broken) clause, consuming it before erroring would make
   RESYNC-TO-NEXT-CLAUSE -- which just looks for the next '.' or EOF --
   skip straight past it and swallow the NEXT, perfectly good, clause
   along with the broken one. Putting it back costs nothing in the
   ordinary case (some other, non-dot token is simply re-returned to the
   caller that already gave up on this parse)."
  (when (eq (tok-type tok) :dot) (setf (pstream-lookahead ps) tok)))

(defun read-term (ps)
  (let ((tok (ps-next-token ps)))
    (case (tok-type tok)
      (:var (tok-value tok))
      (:number (tok-value tok))
      (:string (tok-value tok))
      (:open-list (read-list-tail ps))
      (:open (read-lisp-form-tail ps))
      (:atom
       (if (tok-tight-open-p tok)
           (progn (ps-next-token ps) (cons (tok-value tok) (read-arglist ps (tok-value tok))))
           (tok-value tok)))
      (t (ps-unread-if-dot ps tok)
         (ps-error ps "expected a term, found ~A" (describe-tok tok))))))

(defun read-arglist (ps functor)
  "Comma-separated arguments of a compound term, up to and including the
   matching ')'. FUNCTOR is only used to name the empty-arglist error."
  (when (eq (tok-type (ps-peek-token ps)) :close)
    (ps-error ps "~A() has an empty argument list -- write ~:*~A with no parentheses for a 0-arity atom, or give it at least one argument"
              functor))
  (let ((args (list (read-term ps))))
    (loop
      (let ((tok (ps-next-token ps)))
        (case (tok-type tok)
          (:comma (push (read-term ps) args))
          (:close (return (nreverse args)))
          (t (ps-unread-if-dot ps tok)
             (ps-error ps "expected ',' or ')' in argument list, found ~A" (describe-tok tok))))))))

(defparameter *lisp-form-readtable*
  (let ((rt (copy-readtable nil)))
    (setf (readtable-case rt) :preserve)
    rt)
  "Used only while reading the CONTENTS of a bare-paren Lisp-form escape
   (READ-LISP-FORM-TAIL below). :preserve keeps each symbol's original
   source case intact, so afterward we can tell an upper-case-led Prolog
   variable spelling from a lower-case-led Prolog atom spelling -- the
   same distinction READ-TERM makes everywhere else, just made here by
   inspecting the string CL:READ handed back instead of by our own
   character-class tables.")

(defun lisp-form-var-name-p (name)
  (and (plusp (length name))
       (or (char= (char name 0) #\_) (upper-case-p (char name 0)))))

(defun translate-lisp-form-symbol (sym)
  "SYM came back from CL:READ with its source case preserved. Upper-
   case- or _-led -> a Prolog variable, translated to this engine's own
   ?-prefixed (or bare _) convention; anything else -> a Prolog atom,
   upcased on intern exactly like READ-TERM's own atoms."
  (let ((name (symbol-name sym)))
    (if (lisp-form-var-name-p name)
        (if (string= name "_") (intern "_") (intern (concatenate 'string "?" name)))
        (intern-upcased name))))

(defun translate-lisp-form (form)
  "Walk an object CL:READ handed back, translating every symbol leaf via
   TRANSLATE-LISP-FORM-SYMBOL and leaving numbers/strings/cons structure
   otherwise untouched. NIL (from CL's own reading of '()') maps straight
   onto this engine's own empty-list representation, so an empty list
   written inside a Lisp form already comes out right with no special
   case needed."
  (cond
    ((null form) nil)
    ((consp form) (cons (translate-lisp-form (car form)) (translate-lisp-form (cdr form))))
    ((symbolp form) (translate-lisp-form-symbol form))
    (t form)))

(defun read-lisp-form-tail (ps)
  "The '(' that gets us here already means \"this is Lisp\" (see the file
   banner) -- so rather than re-tokenizing the contents with this file's
   own Prolog-only character classes, hand them straight to CL:READ and
   translate the symbols it returns. The opening '(' is already consumed
   by the caller (READ-TERM); splice a synthetic one back on so CL:READ
   sees a complete list form and stops exactly at the matching ')', then
   advance PS to that same position character-by-character (so line/col
   tracking for any later error stays correct), and translate the
   result. Accepted consequence: Lisp's own lexical rules apply inside
   these forms, not this reader's own -- no '%' comments, and a
   backslash in a string means whatever CL's string reader says it
   means, not this file's \\n/\\t escapes. Every existing use of this
   escape -- arithmetic, comparisons, LISP-EVAL calls -- is exactly the
   well-behaved symbols/numbers/strings/nested-lists CL:READ handles, so
   this is a strict simplification, not a narrowing of what's expressible."
  (let* ((text (pstream-text ps))
         (start (pstream-pos ps))
         (synthetic (concatenate 'string "(" (subseq text start))))
    (multiple-value-bind (form consumed)
        (handler-case
            (let ((*readtable* *lisp-form-readtable*)
                  (*read-eval* nil))
              (with-input-from-string (s synthetic)
                (values (read s) (file-position s))))
          (end-of-file () (ps-error ps "unterminated Lisp-style form"))
          (reader-error (c) (ps-error ps "malformed Lisp-style form: ~A" c)))
      (when (null form)
        (ps-error ps "empty parenthesized form '()' -- write [] for the empty list"))
      (let ((new-pos (+ start (1- consumed))))
        (loop while (< (pstream-pos ps) new-pos) do (ps-advance ps))
        (translate-lisp-form form)))))

(defun read-list-tail (ps)
  "[a, b, c] and [H|T] sugar, up to and including the matching ']' -- the
   opening '[' is already consumed. Produces the same cons/dotted-list
   shape the compound-pattern matcher already understands; [] is NIL."
  (if (eq (tok-type (ps-peek-token ps)) :close-list)
      (progn (ps-next-token ps) nil)
      (let ((elems (list (read-term ps))))
        (loop
          (let ((tok (ps-next-token ps)))
            (case (tok-type tok)
              (:comma (push (read-term ps) elems))
              (:bar
               (let ((tail (read-term ps)))
                 (unless (eq (tok-type (ps-next-token ps)) :close-list)
                   (ps-error ps "expected ']' after list tail"))
                 (return (reduce (lambda (acc elem) (cons elem acc)) elems :initial-value tail))))
              (:close-list (return (reduce (lambda (acc elem) (cons elem acc)) elems :initial-value nil)))
              (t (ps-unread-if-dot ps tok)
                 (ps-error ps "expected ',', '|', or ']' in list, found ~A" (describe-tok tok)))))))))

;; ---------------------------------------------------------------------------
;; Goals: a term, plus the one-time surface-to-internal rewrite for the
;; handful of ISO-familiar comparator spellings and the real semantic fix
;; for `=`. Applied only at goal position -- see the file banner.
;; ---------------------------------------------------------------------------

(defparameter *goal-rewrites*
  (list (cons (intern "=") (intern "UNIFY"))
        (cons (intern "=:=") (intern "="))
        (cons (intern "=\\=") (intern "/="))
        (cons (intern "=<") (intern "<=")))
  "Surface functor -> the functor prolog-engine.lisp's BUILTIN-STEP
   actually dispatches on, for every 2-ary goal this reader recognizes as
   needing translation. `<`, `>`, `>=` need no entry -- same spelling on
   both sides already.")

(defun rewrite-goal (term)
  (if (and (consp term) (cddr term) (null (cdddr term)))
      (let ((target (cdr (assoc (car term) *goal-rewrites*))))
        (if target (cons target (cdr term)) term))
      term))

(defparameter *is-atom* (intern-upcased "is")
  "The interned symbol IS. Not in *GOAL-REWRITES* (it needs no rewriting,
   same spelling in both places), but included in *INFIX-GOAL-ATOMS*
   below so it gets the same infix spelling every ISO-familiar comparator
   does.")

(defparameter *infix-goal-atoms*
  (list *is-atom* (intern "=") (intern "=:=") (intern "=\\=") (intern "=<")
        (intern "<") (intern ">") (intern ">="))
  "Every atom READ-GOAL treats as an infix binary goal operator when it
   appears LOOSE -- i.e. NOT tight against a following '(' -- immediately
   after a complete left-hand term: `is', plus every ISO-familiar
   comparator this reader already accepts in prefix/compound-term form
   (=(A,B), =:=(A,B), etc.). One table and one code path covers all
   eight, since the final step is identical for every one of them: build
   (list OP Left Right) -- the exact shape the prefix/compound-term
   spelling of that same OP already produces -- and hand it to
   REWRITE-GOAL, which already knows how to translate `=', `=:=', `=\\=',
   and `=<' to the functor BUILTIN-STEP actually dispatches on, and
   already leaves `is', `<', `>', `>=' untouched (no entry needed, same
   spelling both places). So BUILTIN-STEP and REWRITE-GOAL needed zero
   changes for any of these eight -- this is purely a second reader-level
   spelling for goals that already existed.
   NO AMBIGUITY, for a reason that generalizes identically to all eight,
   not just `is': under the OLD grammar, a complete term at goal position
   could ONLY be followed by ',', ')', ']', '|', or '.' -- `LEFT is ...',
   `LEFT >= ...', `LEFT = ...' and so on were ALL already guaranteed
   syntax errors (a complete term followed by a bare atom, nothing
   legally connecting them -- the same `- 5'-shaped case the file banner
   already describes). Adding infix syntax for any of them claims exactly
   that previously-illegal continuation and collides with nothing that
   used to parse -- the identical justification already used for `:-'
   (see NECK-TOKEN-P) and for `=' / `=:=' / `=\\=' / `=<'s prefix-form
   rewrites, just applied at the READER level instead of after the fact.
   Tight-paren stays completely unaffected either way: `is(X,Y)',
   `>=(N,Stop)', etc. still parse exactly as they always did, via
   READ-TERM's ordinary :atom/tight-open-p compound-term case -- this
   table is only ever consulted for a LOOSE occurrence, immediately after
   a complete term has already been read in full.
   ONE DELIBERATE NON-FEATURE: no chaining. `X < Y < Z' reads Left=X,
   consumes `<', reads Right=Y, and stops -- producing the complete goal
   (< X Y) with `< Z' left over in the stream, which the caller (READ-
   BODY, or another nested infix check) then rejects as a syntax error
   (an atom where only ','/'.' -- or, now, another *INFIX-GOAL-ATOMS*
   member -- can legally follow). Chained comparison has no defined
   meaning in Prolog to begin with, so erroring here is correct, not a
   gap: exactly this reader's usual \"error, never silently misparse\"
   standard.")

(defun infix-goal-op-follows-p (ps)
  "T if the NEXT token (not yet consumed) is one of *INFIX-GOAL-ATOMS*,
   written loose. See *INFIX-GOAL-ATOMS*'s own commentary for why this
   can never collide with the existing tight-paren compound-term spelling
   of the same operator, or with anything that used to parse successfully."
  (let ((tok (ps-peek-token ps)))
    (and (eq (tok-type tok) :atom)
         (member (tok-value tok) *infix-goal-atoms*)
         (not (tok-tight-open-p tok)))))

(defun read-goal (ps)
  "A goal is either a plain term (rewritten via REWRITE-GOAL, as always --
   this is how `=(A,B)' etc.'s existing PREFIX spelling already gets
   translated), or -- new -- LEFT <op> RIGHT for any *INFIX-GOAL-ATOMS*
   member written loose: read a first term, and if such an operator
   follows, consume it, read a second term, and hand (list OP Left Right)
   to REWRITE-GOAL exactly as the prefix spelling already does. LEFT is
   read as an ordinary term, not specifically constrained to a bare
   variable -- `is' and `=' are conventionally written with a variable on
   the left (as every use in this codebase does), but nothing here needs
   to enforce that syntactically: a non-variable LEFT still behaves
   exactly as ISO Prolog's own semantics do, via ordinary unification/
   comparison in BUILTIN-STEP, same as it always has for the prefix
   spelling. See *INFIX-GOAL-ATOMS* for why this introduces no ambiguity
   at all, for any of the eight operators it covers."
  (let ((left (read-term ps)))
    (if (infix-goal-op-follows-p ps)
        (let ((op (tok-value (ps-next-token ps))))
          (rewrite-goal (list op left (read-term ps))))
        (rewrite-goal left))))

;; ---------------------------------------------------------------------------
;; Clause bodies: Goal1 , Goal2 , ... , GoalN . -- comma is a pure
;; separator here, never a term/operator (see file banner); this is what
;; keeps clause bodies flat goal lists, exactly matching every existing
;; hand-written <- clause in this codebase, rather than building a ','/2
;; tree that would then need flattening.
;; ---------------------------------------------------------------------------

(defun read-body (ps)
  (let ((goals (list (read-goal ps))))
    (loop
      (let ((tok (ps-next-token ps)))
        (case (tok-type tok)
          (:dot (return (nreverse goals)))
          (:comma (push (read-goal ps) goals))
          (t (ps-error ps "expected ',' or end of clause '.', found ~A" (describe-tok tok))))))))

;; ---------------------------------------------------------------------------
;; Clauses: `:-` is recognized only here, at the top of a clause -- never
;; as a general operator -- because that's the only place it ever needs
;; recognizing (see file banner). Returns (:fact head), (:rule head
;; goals), or (:directive goals).
;; ---------------------------------------------------------------------------

(defparameter *neck* (intern-upcased ":-"))

(defun neck-token-p (tok)
  (and (eq (tok-type tok) :atom) (eq (tok-value tok) *neck*) (not (tok-tight-open-p tok))))

(defun read-clause (ps)
  (if (neck-token-p (ps-peek-token ps))
      (progn (ps-next-token ps) (list :directive (read-body ps)))
      (let ((head (read-term ps)))
        (let ((tok (ps-next-token ps)))
          (cond
            ((eq (tok-type tok) :dot) (list :fact head))
            ((neck-token-p tok) (list :rule head (read-body ps)))
            (t (ps-error ps "expected ':-' or end of clause '.' after clause head, found ~A"
                         (describe-tok tok))))))))

;; ---------------------------------------------------------------------------
;; Consulting a whole file/string: install every clause, run every
;; directive as it's read (matching classic Prolog "consult" behavior),
;; and on a syntax error, report it and resync to the next top-level '.'
;; instead of aborting the whole load on the first typo.
;; ---------------------------------------------------------------------------

(defun resync-to-next-clause (ps)
  (loop
    (let ((tok (ps-next-token ps)))
      (when (member (tok-type tok) '(:dot :eof)) (return)))))

(defun install-clause (clause)
  (ecase (first clause)
    (:fact (add-clause (second clause) nil))
    (:rule (add-clause (second clause) (third clause)))
    (:directive (run-query (macro-query-form (second clause))))))

(defun consult-edinburgh-string (text &optional (source-name "<string>"))
  "Read and install every clause/directive in TEXT. Returns (values
   installed-count error-messages) -- error-messages is NIL when the
   whole file read cleanly."
  (let ((ps (ps-make text source-name)) (installed 0) (errors nil))
    (loop
      (when (eq (tok-type (ps-peek-token ps)) :eof) (return))
      (handler-case
          (progn (install-clause (read-clause ps)) (incf installed))
        (edinburgh-syntax-error (c)
          (push (edinburgh-syntax-error-text c) errors)
          (format *error-output* "~&~A~%" (edinburgh-syntax-error-text c))
          (resync-to-next-clause ps))))
    (values installed (nreverse errors))))

(defun consult-edinburgh-file (pathname)
  (consult-edinburgh-string
   (with-open-file (in pathname)
     (let ((text (make-string (file-length in))))
       (subseq text 0 (read-sequence text in))))
   (namestring pathname)))

(defun consult (pathname)
  "The ordinary front door: (consult \"family.pl\") reads a real .pl file
   written in Edinburgh notation, installs every fact/rule and runs every
   directive in it -- into the SAME database the bracket syntax's own <-
   and ?- already use, so nothing further is needed to start querying it
   with ?-/?-all/EDINBURGH-QUERY right after this call returns, exactly
   like any classic Prolog top level's own consult/1. Prints a one-line
   summary; returns T if the whole file read cleanly, NIL if any clause
   had a syntax error (each one was already reported to *ERROR-OUTPUT*
   as it happened, and every OTHER clause in the file -- before and after
   a broken one -- is still installed; see RESYNC-TO-NEXT-CLAUSE)."
  (multiple-value-bind (installed errors) (consult-edinburgh-file pathname)
    (if errors
        (format t "~&% ~A consulted: ~D installed, ~D error~[s~;~:;s~] -- see above~%"
                (namestring pathname) installed (length errors) (length errors))
        (format t "~&% ~A consulted: ~D clause~[s~;~:;s~] installed~%"
                (namestring pathname) installed installed))
    (null errors)))

;; ---------------------------------------------------------------------------
;; Small conveniences for interactive use and testing: parse (and, for
;; queries, immediately run) a single string without needing a trailing
;; '.' or a file.
;; ---------------------------------------------------------------------------

(defun edinburgh-term (text)
  "Parse exactly one term from TEXT; errors if anything but layout is
   left over."
  (let ((ps (ps-make text "<term>")))
    (let ((term (read-term ps)))
      (ps-skip-layout ps)
      (unless (ps-eof-p ps) (ps-error ps "unexpected trailing input after term"))
      term)))

(defun edinburgh-query (text)
  "Parse TEXT as comma-separated goals (no leading ':-', no trailing '.'
   required) and run them via RUN-QUERY, exactly like ?- does for the
   bracket syntax."
  (let ((ps (ps-make text "<query>")))
    (let ((goals (list (read-goal ps))))
      (loop
        (ps-skip-layout ps)
        (if (eq (tok-type (ps-peek-token ps)) :comma)
            (progn (ps-next-token ps) (push (read-goal ps) goals))
            (return)))
      (unless (ps-eof-p ps) (ps-error ps "unexpected trailing input after query"))
      (run-query (macro-query-form (nreverse goals))))))
