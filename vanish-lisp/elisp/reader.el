;; VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published
;; by the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; See the LICENSE file for the full text.

;;; reader.el --- S-expression serialization bridge for POP-11 and Lean 4 -*- lexical-binding: t; -*-

;; Copyright (C) 2026 VANISH-LISP Contributors
;; SPDX-License-Identifier: AGPL-3.0-or-later

;;; Commentary:
;; Translates VANISH-LISP S-expressions into POP-11 tagged lists and
;; Lean 4 syntax/certificate obligations.

;;; Code:

(require 'cl-lib)
(require 'grammar)

(defun vl-sexp-to-pop11 (expr)
  "Serialize a VANISH-LISP S-expression EXPR into a POP-11 tagged list string."
  (cond
   ((integerp expr)
    (if (< expr 0)
        (format "[neg %d]" (- expr))
      (number-to-string expr)))
   ((symbolp expr)
    (symbol-name expr))
   ((listp expr)
    (let ((op (car expr))
          (args (cdr expr)))
      (pcase op
        ('+ (vl-fold-binop-pop11 "add" args))
        ('* (vl-fold-binop-pop11 "mul" args))
        ('- (if (= (length args) 1)
                (format "[neg %s]" (vl-sexp-to-pop11 (car args)))
              (format "[sub %s %s]"
                      (vl-sexp-to-pop11 (nth 0 args))
                      (vl-sexp-to-pop11 (nth 1 args)))))
        ('pow (format "[pow %s %s]"
                      (vl-sexp-to-pop11 (nth 0 args))
                      (vl-sexp-to-pop11 (nth 1 args))))
        ('derivative (format "[deriv %s %s]"
                             (symbol-name (nth 0 args))
                             (vl-sexp-to-pop11 (nth 1 args))))
        ('under
         (let ((cs (mapconcat #'vl-constraint-to-pop11 (nth 0 args) " ")))
           (format "[under [%s] %s]" cs (vl-sexp-to-pop11 (nth 1 args)))))
        ('vanish-ideal
         (let ((gens (mapconcat #'vl-sexp-to-pop11 (cdr (nth 0 args)) " ")))
           (format "[ideal [generators %s] %s]" gens (vl-sexp-to-pop11 (nth 1 args)))))
        (_ (error "Unsupported operator for POP-11 serialization: %S" op)))))
   (t (error "Cannot serialize to POP-11: %S" expr))))

(defun vl-fold-binop-pop11 (tag args)
  "Left-fold ARGS into binary POP-11 tagged lists with TAG."
  (cl-reduce (lambda (acc item)
               (format "[%s %s %s]" tag acc (vl-sexp-to-pop11 item)))
             (cdr args)
             :initial-value (vl-sexp-to-pop11 (car args))))

(defun vl-constraint-to-pop11 (c)
  "Serialize constraint C (`(= a b)` or `(!= a b)`) to POP-11."
  (let ((tag (if (eq (car c) '=) "eq" "neq")))
    (format "[%s %s %s]"
            tag
            (vl-sexp-to-pop11 (nth 1 c))
            (vl-sexp-to-pop11 (nth 2 c)))))

(defun vl-sexp-to-lean (expr)
  "Render a VANISH-LISP S-expression EXPR as a Lean 4 term string."
  (cond
   ((integerp expr)
    (if (< expr 0) (format "(%d : ℤ)" expr) (number-to-string expr)))
   ((symbolp expr) (symbol-name expr))
   ((listp expr)
    (let ((op (car expr))
          (args (cdr expr)))
      (pcase op
        ('+ (mapconcat #'vl-sexp-to-lean args " + "))
        ('* (mapconcat #'vl-sexp-to-lean args " * "))
        ('- (if (= (length args) 1)
                (format "(- %s)" (vl-sexp-to-lean (car args)))
              (format "(%s - %s)"
                      (vl-sexp-to-lean (nth 0 args))
                      (vl-sexp-to-lean (nth 1 args)))))
        ('pow (format "(%s ^ %s)"
                      (vl-sexp-to-lean (nth 0 args))
                      (vl-sexp-to-lean (nth 1 args))))
        (_ (error "Unsupported operator for Lean 4 rendering: %S" op)))))
   (t (error "Cannot render to Lean 4: %S" expr))))

(defun vl-collect-vars (expr)
  "Return a sorted list of distinct variable symbols occurring in EXPR."
  (let ((vars nil))
    (cl-labels ((walk (e)
                  (cond
                   ((vl-symbol-p e) (cl-pushnew e vars))
                   ((listp e)
                    (pcase (car e)
                      ('derivative (walk (nth 1 (cdr e))))
                      ('under
                       (dolist (c (nth 0 (cdr e)))
                         (walk (nth 1 c))
                         (walk (nth 2 c)))
                       (walk (nth 1 (cdr e))))
                      (_ (mapc #'walk (cdr e))))))))
      (walk expr))
    (sort vars (lambda (a b) (string< (symbol-name a) (symbol-name b))))))

(provide 'reader)
;;; reader.el ends here
