;;;; system.lisp -- predicates that talk to the operating system: shell commands, external
;;;; programs, environment variables, files.  Text arguments (commands, program names,
;;;; arguments, paths) may be strings, atoms or numbers; STRINGS are recommended, because
;;;; atoms are case-folded ("ls" is the atom LS).
(in-package :qp)
(engine-policy)

(defun sys-error (what detail)
  (throw-error (vector 'system_error what detail)))

(defun exit-status (process)
  "Exit code of a finished PROCESS; 128+N when it was killed by signal N."
  (let ((code (sb-ext:process-exit-code process)))
    (if (eq (sb-ext:process-status process) :signaled) (+ 128 code) code)))

(defun flush-output-streams ()
  (finish-output (out))
  (finish-output *standard-output*)
  (finish-output *error-output*))

(defun run-external (program args &key directory environment (capture nil))
  "Run PROGRAM (searched on PATH) with ARGS, wait, and return (values exit-status output-or-nil).
Standard input and error are inherited; standard output is inherited, or captured when CAPTURE."
  (flush-output-streams)
  (handler-case
      (let* ((out (and capture (make-string-output-stream)))
             (process (apply #'sb-ext:run-program program args
                             :search t :wait t :input t :output (or out t) :error t
                             (append (and directory (list :directory directory))
                                     (and environment
                                          (list :environment (append environment (sb-ext:posix-environ))))))))
        (values (exit-status process) (and out (get-output-stream-string out))))
    (prolog-error (c) (error c))
    (error (c) (sys-error (text->atom "RUN") (princ-to-string c)))))

(defun text-list (l)
  (mapcar #'text-of (proper-term-list l)))

(defun option-value (name options)
  "Argument of the first option NAME(Value) in the Prolog list OPTIONS, or (values nil nil)."
  (dolist (o (proper-term-list options) (values nil nil))
    (let ((o (deref o)))
      (when (and (simple-vector-p o) (= (length o) 2) (eq (svref o 0) name))
        (return (values (svref o 1) t))))))

;;; shell(+Command), shell(+Command, ?Status), shell_output(+Command, ?Status, ?Output)
;;; Command is run by /bin/sh -c.
(defdet shell (cmd) (eql 0 (run-external "/bin/sh" (list "-c" (text-of cmd)))))
(defdet shell (cmd status) (unify status (run-external "/bin/sh" (list "-c" (text-of cmd)))))
(defdet shell_output (cmd status output)
  (multiple-value-bind (code text) (run-external "/bin/sh" (list "-c" (text-of cmd)) :capture t)
    (and (unify status code) (unify output text))))

;;; process_run(+Program, +Args, ?Status)            run Program with the list Args, no shell involved
;;; process_run(+Program, +Args, +Options, ?Status)  Options: cwd(Dir), env(NameEqualsValueList),
;;;                                                  capture(?Output) -- Output = captured stdout
(defdet process_run (prog args status)
  (unify status (run-external (text-of prog) (text-list args))))
(defdet process_run (prog args options status)
  (let* ((dir (option-value (text->atom "CWD") options))
         (env (multiple-value-bind (v found) (option-value (text->atom "ENV") options)
                (and found (text-list v))))
         (cap (multiple-value-list (option-value (text->atom "CAPTURE") options))))
    (multiple-value-bind (code text)
        (run-external (text-of prog) (text-list args)
                      :directory (and dir (text-of dir)) :environment env :capture (second cap))
      (and (unify status code)
           (or (not (second cap)) (unify (first cap) text))))))

;;; environment and files
(defdet getenv (name value)                     ; fails when the variable is not set
  (let ((v (sb-ext:posix-getenv (text-of name)))) (and v (unify value v))))
(defdet current_executable (path) (unify path (namestring sb-ext:*runtime-pathname*)))
(defdet exists_file (path)
  (let ((p (probe-file (text-of path)))) (and p (pathname-name p) t)))
(defdet exists_directory (path)
  (let ((p (probe-file (text-of path)))) (and p (null (pathname-name p)) t)))
(defdet working_directory (old new)
  (let ((cwd (namestring *default-pathname-defaults*)))
    (and (unify old (if (string= cwd "") (namestring (truename ".")) cwd))
         (let ((n (deref new)))
           (or (pv-p n)
               (progn (setf *default-pathname-defaults* (truename (text-of n))) t))))))
(defdet halt (code) (flush-output-streams) (sb-ext:exit :code (ar-eval code) :abort t))
