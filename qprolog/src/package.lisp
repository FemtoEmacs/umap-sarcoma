;;;; package.lisp -- qprolog: a WAM-style Prolog engine in Common Lisp.
(defpackage :qprolog
  (:use :cl)
  (:nicknames :qp)
  (:export #:<- #:declare-dynamic #:add-clause
           #:solve-one #:solve-all #:prepare-query #:run-query
           #:query-vars #:term->lisp #:*qp-out*
           #:load-qp #:reset-database))
