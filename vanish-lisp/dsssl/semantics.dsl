;; VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published
;; by the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; See the LICENSE file for the full text.

;; dsssl/semantics.dsl -- DSSSL denotational mapping rules for VANISH-LISP.
;; Each S-expression form maps to its meaning over the integers, the same
;; meaning Lean's Vanish.Semantics.eval assigns. This is the semantics
;; layer: it says what every expression denotes. The runnable mirror is
;; scheme/vanish.rkt (there is no DSSSL engine on this box); the checked
;; version is lean/Vanish/Semantics.lean.

;; (denote expr env) evaluates expr in env, an association list of
;; (symbol . integer) pairs. It mirrors eval in Vanish.Semantics.
(define (denote expr env)
  (cond
    ((number? expr) expr)
    ((symbol? expr)
     (let ((binding (assoc expr env)))
       (if binding
           (cdr binding)
           (error "denote: unbound symbol" expr))))
    ((null? expr) (error "denote: empty expression"))
    (else
     (let ((op (car expr))
           (args (cdr expr)))
       (cond
         ((eq? op 'add) (+ (denote (car args) env)
                            (denote (cadr args) env)))
         ((eq? op 'sub) (- (denote (car args) env)
                            (denote (cadr args) env)))
         ((eq? op 'mul) (* (denote (car args) env)
                            (denote (cadr args) env)))
         ((eq? op 'pow) (expt (denote (car args) env)
                               (denote (cadr args) env)))
         ((eq? op '-) (- (denote (car args) env)))
         (else (error "denote: unknown operator" op)))))))

;; (vanishes? expr env) is true when the expression denotes zero.
;; This is the denotational form of the vanish1 CD symbol "vanishes":
;; it asserts an expression equals zero.
(define (vanishes? expr env)
  (= (denote expr env) 0))

;; (semantically-vanishes? expr) is true when the expression denotes
;; zero in every environment: the unconditional vanishing judgement.
;; It is the DSSSL form of Lean's SemanticallyVanishes [].
(define (semantically-vanishes? expr)
  ;; Checked structurally: the normal form must be the integer zero.
  (equal? (vanish-normalize expr) 0))
