;;; repl.el --- Interactive REPL for VANISH-LISP -*- lexical-binding: t; -*-

;; Copyright (C) 2026 VANISH-LISP Contributors
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Provides an interactive Emacs REPL and buffer evaluation commands
;; for VANISH-LISP expressions.

;;; Code:

(require 'vanish)
(require 'macros)

(defvar vanish-repl-buffer-name "*VANISH-LISP*"
  "Name of the interactive VANISH-LISP REPL buffer.")

(defun vanish-format-verdict (expr)
  "Format EXPR evaluation with its tri-state vanishing verdict."
  (let* ((reduced (vl-eval-form expr))
         (verdict (vl-vanish-p reduced)))
    (format "%S  [V = %s]"
            reduced
            (pcase verdict
              (1 "1 (vanishes)")
              (0 "0 (non-zero)")
              ('bot "⊥ (undetermined)")))))

;;;###autoload
(defun vanish-eval-expression (expr)
  "Evaluate a VANISH-LISP EXPR interactively and display the verdict."
  (interactive "xVANISH-LISP expr: ")
  (let ((msg (vanish-format-verdict expr)))
    (message "VLISP => %s" msg)
    msg))

;;;###autoload
(defun vanish-repl ()
  "Start or switch to the interactive VANISH-LISP REPL buffer."
  (interactive)
  (let ((buf (get-buffer-create vanish-repl-buffer-name)))
    (with-current-buffer buf
      (erase-buffer)
      (insert ";; VANISH-LISP Symbolic Vanishing Calculator REPL\n")
      (insert ";; Use M-x vanish-eval-expression to evaluate forms.\n\n")
      (insert "VLISP> "))
    (switch-to-buffer buf)))

(provide 'repl)
;;; repl.el ends here
