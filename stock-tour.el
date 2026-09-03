;;; stock-tour.el --- Execute UMAP TOUR.md blocks in Eshell -*- lexical-binding: t; -*-

;; This shared file is intentionally identical in stock-umap and umap-sarcoma.

(require 'eshell)
(require 'subr-x)

(defgroup stock-tour nil
  "Run a UMAP project's guided tour from Markdown."
  :group 'tools)

(defcustom stock-tour-project-root
  (file-name-directory
   (or load-file-name buffer-file-name default-directory))
  "Root directory containing this project's TOUR.md."
  :type 'directory
  :group 'stock-tour)

(defcustom stock-tour-file
  (expand-file-name "TOUR.md" stock-tour-project-root)
  "Markdown tour displayed by `stock-tour-open'."
  :type 'file
  :group 'stock-tour)

(defcustom stock-tour-eshell-buffer-name "*umap-tour-eshell*"
  "Name of the Eshell buffer used by the tour."
  :type 'string
  :group 'stock-tour)

(defvar-local stock-tour--eshell-buffer nil)

(defun stock-tour--block-at-point ()
  "Return the shell source block containing point, or nil.

Only fenced Markdown blocks labelled sh, shell, or bash are executable."
  (save-excursion
    (let ((origin (point)) begin end language)
      (when (re-search-backward
             "^[ \\t]*```[ \\t]*\\(sh\\|shell\\|bash\\)[ \\t]*$"
             nil t)
        (setq language (match-string-no-properties 1)
              begin (line-beginning-position 2))
        (goto-char begin)
        (when (re-search-forward "^[ \\t]*```[ \\t]*$" nil t)
          (setq end (line-beginning-position))
          (when (and (>= origin begin) (<= origin end))
            (list :language language
                  :begin begin
                  :end end
                  :source (string-trim-right
                           (buffer-substring-no-properties begin end)))))))))

(defun stock-tour--eshell-buffer ()
  "Return the live tour Eshell buffer, creating it when necessary."
  (if (buffer-live-p stock-tour--eshell-buffer)
      stock-tour--eshell-buffer
    (setq stock-tour--eshell-buffer
          (save-window-excursion
            (eshell "new")
            (rename-buffer stock-tour-eshell-buffer-name t)
            (current-buffer)))))

(defun stock-tour-execute-block ()
  "Execute the fenced shell block containing point in the lower Eshell.

The complete block is passed to /bin/sh as one script and starts in
`stock-tour-project-root'.  Markdown outside a shell block is never run."
  (interactive)
  (let ((block (stock-tour--block-at-point)))
    (unless block
      (user-error "Point is not inside a fenced sh, shell, or bash block"))
    (let* ((source (plist-get block :source))
           (script (format "cd %s\n%s"
                           (shell-quote-argument
                            (expand-file-name stock-tour-project-root))
                           source))
           (command (format "/bin/sh -c %s" (shell-quote-argument script)))
           (eshell-buffer (stock-tour--eshell-buffer))
           (window (get-buffer-window eshell-buffer)))
      (unless window
        (setq window (split-window (selected-window) nil 'below))
        (set-window-buffer window eshell-buffer))
      (with-selected-window window
        (goto-char (point-max))
        (insert command)
        (eshell-send-input))
      (message "Running TOUR.md shell block in %s"
               stock-tour-eshell-buffer-name))))

(defvar stock-tour-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c e") #'stock-tour-execute-block)
    map)
  "Keymap for `stock-tour-mode'.")

(define-minor-mode stock-tour-mode
  "Execute fenced shell blocks in the current UMAP tour with `C-c e'."
  :lighter " UMAP-Tour"
  :keymap stock-tour-mode-map)

;;;###autoload
(defun stock-tour-open ()
  "Open TOUR.md above a dedicated Eshell window.

Place point anywhere inside a fenced shell block and type `C-c e' to execute
that entire block."
  (interactive)
  (let* ((tour-buffer (find-file-noselect stock-tour-file))
         (eshell-buffer
          (with-current-buffer tour-buffer
            (stock-tour-mode 1)
            (stock-tour--eshell-buffer))))
    (delete-other-windows)
    (switch-to-buffer tour-buffer)
    (setq-local stock-tour--eshell-buffer eshell-buffer)
    (let ((bottom (split-window (selected-window) nil 'below)))
      (set-window-buffer bottom eshell-buffer)
      (with-current-buffer eshell-buffer
        (setq default-directory (file-name-as-directory
                                 (expand-file-name stock-tour-project-root))))
      (select-window (get-buffer-window tour-buffer))
      (goto-char (point-min))
      (message "UMAP tour ready: put point in a shell block and type C-c e"))))

(provide 'stock-tour)
;;; stock-tour.el ends here
