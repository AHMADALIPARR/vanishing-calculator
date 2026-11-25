;; dsssl/reduction.dsl -- DSSSL symbolic reduction rules for VANISH-LISP.
;; DSSSL is standardized under ISO/IEC 10179:1996. These rules are the
;; Scheme layer of the pipeline: the same rules, in runnable form, live
;; in scheme/vanish.rkt, because there is no DSSSL engine (no
;; Jade/OpenJade) on this box. The two rules below are the rules as
;; supplied; the rules after them are additions in the same style,
;; covering the full rewrite set of pop11/rewrite.p.

(define (vanish-sub a b)
  (if (equal? a b)
      0
      (list 'sub a b)))

(define (vanish-mul a b)
  (cond
    ((equal? a 0) 0)
    ((equal? b 0) 0)
    (else (list 'mul a b))))

;; ADDITIONS (same style, full rewrite set):

(define (vanish-add a b)
  (cond
    ((equal? a 0) b)
    ((equal? b 0) a)
    (else (list 'add a b))))

(define (vanish-pow a n)
  (cond
    ((equal? n 0) 1)
    ((equal? n 1) a)
    (else (list 'pow a n))))

(define (vanish-neg a)
  (if (equal? a 0)
      0
      (list '- a)))

(define (vanish-normalize expr)
  (cond
    ((number? expr) expr)
    ((symbol? expr) expr)
    ((null? expr) expr)
    (else
     (let ((op (car expr))
           (args (map vanish-normalize (cdr expr))))
       (cond
         ((eq? op 'sub) (vanish-sub (car args) (cadr args)))
         ((eq? op 'add) (vanish-add (car args) (cadr args)))
         ((eq? op 'mul) (vanish-mul (car args) (cadr args)))
         ((eq? op 'pow) (vanish-pow (car args) (cadr args)))
         ((eq? op '-) (vanish-neg (car args)))
         (else (cons op args)))))))
