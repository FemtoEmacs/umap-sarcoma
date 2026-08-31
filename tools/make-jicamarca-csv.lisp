;;;; Reproducibly convert the canonical Jicamarca S-expression to CSV.

(defun csv-field (value stream)
  (let ((text (princ-to-string value)))
    (if (or (find #\, text) (find #\" text) (find #\Newline text))
        (progn
         (write-char #\" stream)
         (loop for character across text
               do (when (char= character #\")
                    (write-char #\" stream)) (write-char character stream))
         (write-char #\" stream))
        (write-string text stream))))

(let* ((arguments (cdr *posix-argv*))
       (input (first arguments))
       (causal-input (second arguments))
       (sexpr-output (third arguments))
       (csv-output (fourth arguments))
       (keys
        '(:event :time :local-time :day :f107 :observed :measurement-error :sf99
          :residual :effect :support :high-count :low-count))
       (data
        (with-open-file (stream input)
          (let ((*read-eval* nil))
            (read stream))))
       (causal
        (with-open-file (stream causal-input)
          (let ((*read-eval* nil))
            (read stream))))
       (records
        (loop for observation in (getf data :records)
              for annotation in (getf causal :records)
              collect (append observation annotation))))
  (with-open-file
      (stream sexpr-output :direction :output :if-exists :supersede :if-does-not-exist
       :create)
    (let ((*print-pretty* t) (*print-right-margin* 110))
      (write (list :records records) :stream stream)
      (terpri stream)))
  (with-open-file
      (stream csv-output :direction :output :if-exists :supersede :if-does-not-exist
       :create)
    (format stream
            (concatenate
             'string
             "event,time,local_time,day,f107,observed,measurement_error,"
             "sf99,residual,effect,support,high_count,low_count~%"))
    (dolist (record records)
      (loop for key in keys
            for first = t then nil
            do (unless first
                 (write-char #\, stream)) (csv-field (getf record key) stream))
      (terpri stream))))
