;;; grammar.el --- Mathematical grammar and AST predicates for VANISH-LISP -*- lexical-binding: t; -*-

;; Copyright (C) 2026 VANISH-LISP Contributors
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Defines the restricted mathematical grammar of VANISH-LISP.
;; Expressions are limited to total ring operations (+, -, *, pow),
;; symbolic differentiation (derivative), assumptions (under), and
;; ideal membership queries (vanish-ideal, residue).

;;; Code:

(require 'cl-lib)

(defconst vl-ring-operators '(+ - * pow)
  "Total ring operators permitted in VANISH-LISP expressions.")

(defconst vl-core-primitives
  '(vanish reduce normalize under derivative vanish-ideal residue witness seal)
  "Core primitives of the VANISH-LISP dialect.")

(defun vl-symbol-p (x)
  "Return non-nil if X is a valid mathematical variable symbol."
  (and (symbolp x)
       (not (memq x '(t nil)))
       (not (memq x vl-ring-operators))
       (not (memq x vl-core-primitives))))

(defun vl-constraint-p (c)
  "Return non-nil if C is a valid constraint form (= a b) or (!= a b)."
  (and (listp c)
       (= (length c) 3)
       (memq (car c) '(= !=))
       (vl-expr-p (nth 1 c))
       (vl-expr-p (nth 2 c))))

(defun vl-expr-p (expr)
  "Return non-nil if EXPR is a well-formed VANISH-LISP mathematical expression."
  (cond
   ((integerp expr) t)
   ((vl-symbol-p expr) t)
   ((not (listp expr)) nil)
   ((null expr) nil)
   (t
    (let ((op (car expr))
          (args (cdr expr)))
      (pcase op
        ('+ (and (>= (length args) 2)
                 (cl-every #'vl-expr-p args)))
        ('- (and (or (= (length args) 1) (= (length args) 2))
                 (cl-every #'vl-expr-p args)))
        ('* (and (>= (length args) 2)
                 (cl-every #'vl-expr-p args)))
        ('pow (and (= (length args) 2)
                   (vl-expr-p (nth 0 args))
                   (integerp (nth 1 args))
                   (>= (nth 1 args) 0)))
        ('derivative (and (= (length args) 2)
                          (vl-symbol-p (nth 0 args))
                          (vl-expr-p (nth 1 args))))
        ('under (and (= (length args) 2)
                     (listp (nth 0 args))
                     (cl-every #'vl-constraint-p (nth 0 args))
                     (vl-expr-p (nth 1 args))))
        (_ nil))))))

(defun vl-validate-expr (expr)
  "Signal an error if EXPR is not a valid VANISH-LISP expression."
  (unless (vl-expr-p expr)
    (error "Invalid VANISH-LISP expression: %S" expr))
  expr)

(provide 'grammar)
;;; grammar.el ends here
