(load "smc-trainer/shards.lisp")

(let ((source (parametric-open-corpus-source "smc-trainer/corpus/pilot-shards/manifest.sexp"))
      (index 0))
  (parametric-map-records source (lambda (record)
				   (when (evenp index) (format t "~S~%" record)) (incf index))))
