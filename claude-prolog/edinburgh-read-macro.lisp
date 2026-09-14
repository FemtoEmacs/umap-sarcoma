;;;; edinburgh-read-macro.lisp -- a Lisp READ-macro for embedding Edinburgh-
;;;; notation queries directly in Lisp source/at the REPL, 2026-09-14.
;;;; Load AFTER prolog-engine.lisp and edinburgh-reader.lisp.
;;;;
;;;; WHAT THIS BUYS: instead of typing
;;;;   (edinburgh-query "app(Left, Right, [3,4.5])")
;;;; as a Lisp string, once this file's readtable is active you can just
;;;; write
;;;;   ?-app(Left, Right, [3,4.5]);
;;;; directly as Lisp source (top level, or nested inside any other form --
;;;; it reads as an ordinary object, (EDINBURGH-QUERY "app(...)"), that
;;;; gets evaluated wherever it appears, exactly like any other form).
;;;;
;;;; THE DISAMBIGUATION RULE, stated once, since it's the only thing that
;;;; makes this safe to turn on globally in a codebase that already uses
;;;; '?x'-style pvar symbols and the existing bracket-syntax ?-/?-all query
;;;; macros pervasively, everywhere: '?' becomes a (non-terminating) Lisp
;;;; macro character whose reader function fires only on '?' as the FIRST
;;;; character of a fresh token (non-terminating -- '?' occurring mid-
;;;; symbol, which never happens in this codebase anyway, is untouched).
;;;; From there:
;;;;   - '?' not immediately followed by '-'                => ordinary
;;;;     symbol reading, unchanged: ?x, ?_foo, ?, etc. read exactly as they
;;;;     always have (case-upcased, interned) -- this is the common case
;;;;     and must never regress, since every existing file in this project
;;;;     depends on it.
;;;;   - '?-' followed (optional whitespace) by a lowercase-letter-led
;;;;     identifier that is then TIGHT against '(' (no space) -- exactly
;;;;     the same tight-paren-means-compound-term convention
;;;;     edinburgh-reader.lisp already uses to tell a compound term from
;;;;     everything else -- is the new form: read raw characters (tracking
;;;;     paren/bracket depth and skipping over quoted regions) up to the
;;;;     first top-level ';', and hand the whole thing to EDINBURGH-QUERY.
;;;;   - '?-' in EVERY other shape -- followed by a space then '(' (the
;;;;     existing bracket-syntax (?- (goal)) and (?-all (goal)) macros,
;;;;     always written this way), or by nothing tight-paren-following at
;;;;     all -- falls all the way through to ordinary symbol reading of
;;;;     '?-'/'?-all'/whatever, unchanged. '?-all (foo)' keeps meaning what
;;;;     it always has; only a TIGHT '?-someatom(' is new syntax.
;;;; So the two syntaxes cannot collide: nothing in this codebase (or in
;;;; ordinary Lisp style generally) ever writes a C-like tight call
;;;; 'symbol(args)' -- that shape simply didn't parse as anything useful
;;;; before this file existed.
;;;;
;;;; WHY ';', GIVEN IT'S ALREADY LISP'S COMMENT CHARACTER -- "accommodating
;;;; available characters" here means NOT touching ';'s own readtable entry
;;;; at all, so line comments everywhere else (including right after a
;;;; captured query -- '?-app(X, Y, Z); ; ordinary comment' works fine) are
;;;; completely undisturbed. READ-EDINBURGH-RAW-UNTIL-SEMICOLON does its
;;;; own raw character scan looking for a literal ';' -- it never asks the
;;;; reader to interpret that character at all, so ';' never needs to mean
;;;; anything different globally. '.' was considered and rejected: it's
;;;; already meaningful to the Lisp reader (dotted-pair syntax) in a way
;;;; that would collide the moment a query contained a float literal or a
;;;; [H|T]-style list, e.g. '?-list-len([a,b|T], N).' -- ';' has no such
;;;; conflict once we're doing our own raw scan instead of asking the
;;;; standard tokenizer to make sense of it.
;;;;
;;;; ENABLING THIS: (enable-edinburgh-syntax) sets *READTABLE* globally for
;;;; the rest of the session/script -- safe to do, per the disambiguation
;;;; above. For scoped use instead, bind
;;;;   (let ((*readtable* *edinburgh-lisp-readtable*)) ...)
;;;; around just the forms that need it. (disable-edinburgh-syntax) restores
;;;; the plain standard readtable.

(load "prolog-engine.lisp")
(load "edinburgh-reader.lisp")

(defun lisp-token-terminates-p (ch)
  "T if CH would end an ordinary Lisp token under the readtable this file
   started from -- whitespace, or a terminating macro character. Used
   only to fall BACK to plain symbol reading once we've determined '?...'
   isn't an embedded Edinburgh query -- see READ-PLAIN-SYMBOL-TAIL."
  (or (null ch)
      (member ch '(#\Space #\Tab #\Newline #\Return #\Linefeed #\Page))
      (multiple-value-bind (fn non-terminating-p) (get-macro-character ch)
        (and fn (not non-terminating-p)))))

(defun read-plain-symbol-tail (stream prefix)
  "Reconstruct ordinary Lisp symbol-token reading for a token that starts
   with PREFIX (already consumed from STREAM, never including any
   whitespace -- whitespace always ends a token and is simply discarded,
   exactly as the standard reader already does). This is what makes
   turning '?' into a macro character safe: every character PREFIX didn't
   already commit to being part of THIS token still gets read normally."
  (let ((rest (with-output-to-string (out)
                (loop for ch = (peek-char nil stream nil nil)
                      until (lisp-token-terminates-p ch)
                      do (write-char (read-char stream) out)))))
    (intern (string-upcase (concatenate 'string prefix rest)))))

(defun edinburgh-ident-start-p (ch) (and ch (alpha-char-p ch) (lower-case-p ch)))

(defun read-edinburgh-raw-until-semicolon (stream)
  "Called with the stream positioned right at the '(' that opens an
   embedded query's argument list (not yet consumed). Reads raw
   characters -- tracking ()/[] depth and skipping over '...'/\"...\"
   quoted regions (respecting a backslash escape inside them, so an
   escaped quote character doesn't end the region early) -- up to and
   including the first ';' at depth 0, returning everything EXCEPT that
   final ';' itself. This is a raw scan, not a parse: a malformed capture
   still surfaces as an ordinary, clear EDINBURGH-SYNTAX-ERROR once
   EDINBURGH-QUERY actually tries to parse it -- this function's only job
   is finding where to stop reading from the Lisp stream."
  (with-output-to-string (out)
    (let ((depth 0))
      (loop
        (let ((ch (read-char stream nil nil)))
          (cond
            ((null ch)
             (error "unterminated ?-...; embedded Edinburgh query (missing closing ';')"))
            ((and (char= ch #\;) (zerop depth))
             (return))
            (t
             (write-char ch out)
             (case ch
               ((#\( #\[) (incf depth))
               ((#\) #\]) (decf depth))
               ((#\' #\")
                (read-edinburgh-quoted-tail stream ch out))))))))))

(defun read-edinburgh-quoted-tail (stream close out)
  "Helper for READ-EDINBURGH-RAW-UNTIL-SEMICOLON: OUT already has the
   opening quote character CLOSE written to it; copies characters
   (respecting one backslash escape at a time) through to, and
   including, the matching closing CLOSE."
  (loop
    (let ((c2 (read-char stream nil nil)))
      (when (null c2)
        (error "unterminated ?-...; embedded Edinburgh query (unterminated ~C...~C)" close close))
      (write-char c2 out)
      (cond
        ((char= c2 #\\)
         (let ((c3 (read-char stream nil nil)))
           (unless c3
             (error "unterminated ?-...; embedded Edinburgh query (unterminated ~C...~C)" close close))
           (write-char c3 out)))
        ((char= c2 close) (return))))))

(defun edinburgh-query-reader (stream char)
  (declare (ignore char))
  (if (eql (peek-char nil stream nil nil) #\-)
      (progn
        (read-char stream) ; consume '-'
        ;; Optional whitespace between '?-' and the identifier -- matches
        ;; how '?- goal.' reads naturally in real Prolog toplevels, and
        ;; can't collide: any whitespace here already means "not tight",
        ;; so a real match still requires NO space right before the '('.
        (loop while (member (peek-char nil stream nil nil) '(#\Space #\Tab))
              do (read-char stream))
        (if (edinburgh-ident-start-p (peek-char nil stream nil nil))
            (let ((ident (with-output-to-string (out)
                           (loop for ch = (peek-char nil stream nil nil)
                                 while (atom-ident-char-p ch)
                                 do (write-char (read-char stream) out)))))
              (if (eql (peek-char nil stream nil nil) #\()
                  `(edinburgh-query ,(concatenate 'string ident (read-edinburgh-raw-until-semicolon stream)))
                  (read-plain-symbol-tail stream (concatenate 'string "?-" ident))))
            (read-plain-symbol-tail stream "?-")))
      (read-plain-symbol-tail stream "?")))

(defvar *edinburgh-lisp-readtable*
  (let ((rt (copy-readtable nil)))
    (set-macro-character #\? #'edinburgh-query-reader t rt)
    rt)
  "A copy of the standard readtable with '?' bound to EDINBURGH-QUERY-
   READER (non-terminating, so '?' mid-token -- never used in this
   codebase, but just in case -- stays an ordinary constituent character).
   Bind *READTABLE* to this (globally via ENABLE-EDINBURGH-SYNTAX, or
   scoped with a LET) to activate '?-pred(...);' query syntax.")

(defvar *plain-lisp-readtable* (copy-readtable nil)
  "The ordinary standard readtable, saved once at load time, so
   DISABLE-EDINBURGH-SYNTAX has something definite to restore.")

(defun enable-edinburgh-syntax ()
  "Sets *READTABLE* globally, for the rest of this session/script, to
   accept '?-pred(...);' as an embedded Edinburgh query. Safe to leave on:
   see this file's banner comment for why the two syntaxes can't collide."
  (setf *readtable* *edinburgh-lisp-readtable*)
  t)

(defun disable-edinburgh-syntax ()
  "Restores the plain standard readtable."
  (setf *readtable* *plain-lisp-readtable*)
  t)
