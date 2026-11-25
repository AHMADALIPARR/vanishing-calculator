;; VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published
;; by the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; See the LICENSE file for the full text.

;;; vanish.el --- Core symbolic vanishing normalizer and bridges -*- lexical-binding: t; -*-

;; Copyright (C) 2026 VANISH-LISP Contributors
;; SPDX-License-Identifier: AGPL-3.0-or-later

;;; Commentary:
;; Implements the initial Emacs Lisp symbolic reducer, differentiation,
;; constraint substitution, and optional subprocess bridges to POP-11
;; and Lean 4.

;;; Code:

(require 'cl-lib)
(require 'grammar)
(require 'reader)

(defgroup vanish-lisp nil
  "VANISH-LISP symbolic vanishing calculator."
  :group 'languages)

(defcustom vl-pop11-executable "pop11"
  "Path to the POP-11 executable for symbolic reduction."
  :type 'string
  :group 'vanish-lisp)

(defcustom vl-lean-executable "lake"
  "Path to the Lean Lake executable for proof verification."
  :type 'string
  :group 'vanish-lisp)

(defun vl-normalize-product (args)
  "Normalize a product ARGS: drop factors of 1, fold integer constants.
Returns the constant alone when every factor is constant, a single
factor alone when one non-constant factor remains, or (* const rest)
with the folded constant first."
  (let ((const 1)
        (rest nil))
    (dolist (a args)
      (if (integerp a)
          (setq const (* const a))
        (push a rest)))
    (setq rest (nreverse rest))
    (cond
     ((null rest) const)
     ((= const 1) (if (= (length rest) 1) (car rest) (cons '* rest)))
     (t (cons '* (cons const rest))))))

(defun vl-normalize (expr)
  "Normalize EXPR using total ring algebraic identities."
  (if (atom expr)
      expr
    (let* ((op (car expr))
           (args (mapcar #'vl-normalize (cdr expr)))
           (a (car args))
           (b (cadr args)))
      (cond
       ;; Subtraction identities
       ((and (eq op '-) (= (length args) 1) (integerp a))
        (- a))
       ((and (eq op '-) (= (length args) 2) (integerp a) (integerp b))
        (- a b))
       ((and (eq op '-) (= (length args) 2) (equal a b))
        0)
       ((and (eq op '-) (= (length args) 2) (equal b 0))
        a)
       ;; Multiplication identities (n-argument: drop 1s, fold constants)
       ((and (eq op '*) (member 0 args))
        0)
       ((eq op '*)
        (vl-normalize-product args))
       ;; Addition identities
       ((and (eq op '+) (= (length args) 2) (integerp a) (integerp b))
        (+ a b))
       ((and (eq op '+) (= (length args) 2) (equal a 0))
        b)
       ((and (eq op '+) (= (length args) 2) (equal b 0))
        a)
       ;; Power identities
       ((and (eq op 'pow) (= (length args) 2) (equal b 0))
        1)
       ((and (eq op 'pow) (= (length args) 2) (equal b 1))
        a)
       ((and (eq op 'pow) (= (length args) 2) (integerp a) (integerp b))
        (expt a b))
       (t (cons op args))))))

(defun vl-substitute (var val expr)
  "Substitute VAR with VAL inside EXPR."
  (cond
   ((eq expr var) val)
   ((atom expr) expr)
   (t (cons (car expr)
            (mapcar (lambda (arg) (vl-substitute var val arg)) (cdr expr))))))

(defun vl-apply-constraints (constraints expr)
  "Apply equational CONSTRAINTS of the form ((= x y) ...) to EXPR."
  (let ((cur expr))
    (dolist (c constraints cur)
      (when (and (listp c) (eq (car c) '=))
        (let ((lhs (nth 1 c))
              (rhs (nth 2 c)))
          (when (vl-symbol-p lhs)
            (setq cur (vl-substitute lhs rhs cur))))))))

(defun vl-derivative (var expr)
  "Compute the symbolic derivative of EXPR with respect to VAR."
  (vl-normalize
   (cond
    ((integerp expr) 0)
    ((symbolp expr) (if (eq expr var) 1 0))
    ((listp expr)
     (let ((op (car expr))
           (args (cdr expr)))
       (pcase op
         ('+ (cons '+ (mapcar (lambda (e) (vl-derivative var e)) args)))
         ('- (if (= (length args) 1)
                 (list '- (vl-derivative var (car args)))
               (list '-
                     (vl-derivative var (nth 0 args))
                     (vl-derivative var (nth 1 args)))))
         ('* (if (= (length args) 2)
                 (let ((u (nth 0 args))
                       (v (nth 1 args)))
                   (list '+
                         (list '* (vl-derivative var u) v)
                         (list '* u (vl-derivative var v))))
               (let ((u (car args))
                     (rest (cons '* (cdr args))))
                 (list '+
                       (list '* (vl-derivative var u) rest)
                       (list '* u (vl-derivative var rest))))))
         ('pow (let ((base (nth 0 args))
                     (exp (nth 1 args)))
                 (if (= exp 0)
                     0
                   (list '*
                         exp
                         (list 'pow base (1- exp))
                         (vl-derivative var base)))))
         (_ (error "Cannot differentiate form: %S" expr)))))
    (t 0))))

(defun vl-vanish-p (expr)
  "Return tri-state vanishing verdict: 1 (vanishes), 0 (non-zero), or `bot'."
  (let ((norm (vl-normalize expr)))
    (cond
     ((equal norm 0) 1)
     ((integerp norm) 0)
     (t 'bot))))

(defun vl-eval-form (expr)
  "Evaluate a VANISH-LISP expression EXPR in the local Elisp reducer."
  (cond
   ((atom expr) (vl-normalize expr))
   ((eq (car expr) 'derivative)
    (vl-derivative (nth 1 expr) (vl-eval-form (nth 2 expr))))
   ((eq (car expr) 'under)
    (vl-normalize (vl-apply-constraints (nth 1 expr) (vl-eval-form (nth 2 expr)))))
   (t (vl-normalize (cons (car expr) (mapcar #'vl-eval-form (cdr expr)))))))

(defun vl-emit-lean-theorem (name expr &optional constraints)
  "Generate a Lean 4 theorem string named NAME asserting `vanishes[EXPR]`."
  (let* ((vars (vl-collect-vars expr))
         (binders (if vars
                      (mapconcat (lambda (v) (format "(%s : ℤ)" (symbol-name v)))
                                 vars " ")
                    ""))
         (hyps (if constraints
                   (mapconcat (lambda (c)
                                (format "(h_%s : %s = %s)"
                                        (vl-sexp-to-lean (nth 1 c))
                                        (vl-sexp-to-lean (nth 1 c))
                                        (vl-sexp-to-lean (nth 2 c))))
                              constraints " ")
                 "")))
    (format "theorem %s %s %s :\n    vanishes[%s] := by\n  vanish_solve\n"
            name binders hyps (vl-sexp-to-lean expr))))

(provide 'vanish)
;;; vanish.el ends here
