#lang racket
;; scheme/vanish.rkt -- Runnable Racket mirror of the DSSSL rules and the
;; S-expression front end of the VANISH-LISP pipeline.
;;
;; There is no DSSSL engine on this box, so this file is the layer that
;; actually runs: it implements the DSSSL reduction and semantics rules
;; (dsssl/reduction.dsl, dsssl/semantics.dsl) in Racket, normalizes
;; S-expressions, and emits the two interchange forms the pipeline
;; consumes: vanish XML (the SGML/DTD form) and OpenMath (the canonical
;; mathematical IR). The rewrite rules here are the same rules as
;; pop11/rewrite.p and Lean's Vanish.Soundness.Step.
;;
;; Operator names: the surface S-expression syntax uses + - * pow (see
;; ir/grammar.ebnf); the DSSSL rules use add sub mul pow. Both spellings
;; are accepted everywhere here. The normal form uses add sub mul pow,
;; matching the DSSSL rules and the vanish XML element names.
;;
;; Usage:
;;   racket vanish.rkt --xml in.sexp out.xml
;;   racket vanish.rkt --openmath in.sexp out.om
;;   racket vanish.rkt --normalize in.sexp
;;   racket vanish.rkt --selftest

(provide vanish-sub vanish-mul vanish-add vanish-pow vanish-neg
         vanish-normalize denote vanishes? sexp->xml sexp->openmath)

;; ---- Reduction rules (DSSSL reduction.dsl, same names and semantics) ----

(define (vanish-sub a b)
  (if (equal? a b)
      0
      (list 'sub a b)))

(define (vanish-mul a b)
  (cond
    ((equal? a 0) 0)
    ((equal? b 0) 0)
    (else (list 'mul a b))))

;; Additions in the same style, covering the full rewrite set.
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

;; ---- Full normalizer (bottom-up, n-ary + and *) ----

(define (fold-constants args)
  ;; Split normalized args into integer constants and symbolic args.
  ;; Returns (values consts rest).
  (let loop ((as args) (consts '()) (rest '()))
    (cond
      ((null? as) (values (reverse consts) (reverse rest)))
      ((integer? (car as)) (loop (cdr as) (cons (car as) consts) rest))
      (else (loop (cdr as) consts (cons (car as) rest))))))

(define (normalize-add args)
  (let-values (((consts rest) (fold-constants args)))
    (let ((sum (apply + 0 consts)))
      (cond
        ((and (null? rest) (null? consts)) 0)
        ((null? rest) sum)
        ((zero? sum) (if (= (length rest) 1) (car rest) (cons 'add rest)))
        (else (cons 'add (cons sum rest)))))))

(define (normalize-mul args)
  (cond
    ((member 0 args) 0)
    (else
     (let-values (((consts rest) (fold-constants args)))
       (let ((prod (apply * 1 consts)))
         (cond
           ((and (null? rest) (null? consts)) 1)
           ((null? rest) prod)
           ((= prod 1) (if (= (length rest) 1) (car rest) (cons 'mul rest)))
           (else (cons 'mul (cons prod rest)))))))))

(define (vanish-normalize expr)
  (cond
    ((or (number? expr) (symbol? expr) (null? expr)) expr)
    (else
     (let ((op (car expr))
           (args (map vanish-normalize (cdr expr))))
       (cond
         ((or (eq? op 'sub) (eq? op '-))
          (if (= (length args) 1)
              (vanish-neg (car args))
              (vanish-sub (car args) (cadr args))))
         ((or (eq? op 'add) (eq? op '+)) (normalize-add args))
         ((or (eq? op 'mul) (eq? op '*)) (normalize-mul args))
         ((eq? op 'pow) (vanish-pow (car args) (cadr args)))
         (else (cons op args)))))))

;; ---- Denotational semantics (DSSSL semantics.dsl) ----

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
         ((or (eq? op 'add) (eq? op '+))
          (+ (denote (car args) env) (denote (cadr args) env)))
         ((or (eq? op 'sub) (eq? op '-))
          (if (= (length args) 1)
              (- (denote (car args) env))
              (- (denote (car args) env) (denote (cadr args) env))))
         ((or (eq? op 'mul) (eq? op '*))
          (* (denote (car args) env) (denote (cadr args) env)))
         ((eq? op 'pow) (expt (denote (car args) env) (denote (cadr args) env)))
         (else (error "denote: unknown operator" op)))))))

(define (vanishes? expr env)
  (= (denote expr env) 0))

;; ---- Operator spelling ----

(define (canonical-op op)
  ;; Surface spelling (+ - *) and DSSSL spelling (add sub mul) both map
  ;; to the canonical element/operator name.
  (case op
    ((sub -) 'sub)
    ((add +) 'add)
    ((mul *) 'mul)
    ((pow) 'pow)
    (else #f)))

;; ---- S-expression to vanish XML (the SGML/DTD form) ----

(define (xml-escape s)
  (let ((s (if (string? s) s (format "~a" s))))
    (string-replace
     (string-replace
      (string-replace s "&" "&amp;") "<" "&lt;") ">" "&gt;")))

(define (expr->xml-inner expr)
  ;; An <expr> element's content for one expression.
  (cond
    ((integer? expr) (format "<integer>~a</integer>" expr))
    ((symbol? expr) (format "<symbol>~a</symbol>" (xml-escape (symbol->string expr))))
    ((and (list? expr) (member (car expr) '(- sub)) (= (length expr) 2))
     ;; Unary minus is encoded as subtraction from zero, the same
     ;; encoding Lean's Vanish.Pipeline.compile uses.
     (format "<sub><expr><integer>0</integer></expr><expr>~a</expr></sub>"
             (expr->xml-inner (cadr expr))))
    ((and (list? expr) (canonical-op (car expr)))
     (let ((op (canonical-op (car expr)))
           (args (cdr expr)))
       ;; The DTD is binary: nest n-ary + and * left-associatively.
       (let ((nested (foldl (lambda (a acc) (list op acc a))
                            (car args) (cdr args))))
         (format "<~a><expr>~a</expr><expr>~a</expr></~a>"
                 op
                 (expr->xml-inner (cadr nested))
                 (expr->xml-inner (caddr nested))
                 op))))
    (else (error "sexp->xml: unsupported expression" expr))))

(define (sexp->xml expr)
  (let ((inner (if (and (list? expr) (eq? (car expr) 'vanish))
                   (cadr expr)
                   expr)))
    (format "<vanish><expr>~a</expr></vanish>" (expr->xml-inner inner))))

;; ---- S-expression to OpenMath (the canonical IR) ----

(define (expr->openmath expr)
  (cond
    ((integer? expr) (format "<OMI>~a</OMI>" expr))
    ((symbol? expr) (format "<OMV name=\"~a\"/>" (xml-escape (symbol->string expr))))
    ((and (list? expr) (member (car expr) '(- sub)) (= (length expr) 2))
     (format "<OMA><OMS cd=\"arith1\" name=\"unary_minus\"/>~a</OMA>"
             (expr->openmath (cadr expr))))
    ((and (list? expr) (canonical-op (car expr)))
     (let ((op (canonical-op (car expr)))
           (args (cdr expr))
           (cdname (case (canonical-op (car expr))
                     ((sub) "minus") ((add) "plus")
                     ((mul) "times") ((pow) "power"))))
       (let ((nested (foldl (lambda (a acc) (list op acc a))
                            (car args) (cdr args))))
         (format "<OMA><OMS cd=\"arith1\" name=\"~a\"/>~a~a</OMA>"
                 cdname
                 (expr->openmath (cadr nested))
                 (expr->openmath (caddr nested))))))
    (else (error "sexp->openmath: unsupported expression" expr))))

(define (sexp->openmath expr)
  (if (and (list? expr) (eq? (car expr) 'vanish))
      (format "<OMOBJ><OMA><OMS cd=\"vanish1\" name=\"vanishes\"/>~a</OMA></OMOBJ>"
              (expr->openmath (cadr expr)))
      (format "<OMOBJ>~a</OMOBJ>" (expr->openmath expr))))

;; ---- Command line ----

(define (read-sexp-file path)
  (call-with-input-file path read))

(define (selftest)
  (define failures 0)
  (define (check name got want)
    (if (equal? got want)
        (printf "PASS ~a\n" name)
        (begin
          (set! failures (+ failures 1))
          (printf "FAIL ~a: got ~a want ~a\n" name got want))))
  (check "vanish-sub self" (vanish-sub 'x 'x) 0)
  (check "vanish-sub diff" (vanish-sub 'x 'y) '(sub x y))
  (check "vanish-mul zero" (vanish-mul 'x 0) 0)
  (check "vanish-mul one" (vanish-mul 'x 1) '(mul x 1))
  (check "normalize sub self" (vanish-normalize '(- x x)) 0)
  (check "normalize mul zero" (vanish-normalize '(* x 0)) 0)
  (check "normalize add zero" (vanish-normalize '(+ x 0)) 'x)
  (check "normalize pow one" (vanish-normalize '(pow x 1)) 'x)
  (check "normalize pow zero" (vanish-normalize '(pow x 0)) 1)
  (check "normalize n-ary mul" (vanish-normalize '(* 2 x 1)) '(mul 2 x))
  (check "normalize nonvanish" (vanish-normalize '(- x y)) '(sub x y))
  (check "normalize quartic" (vanish-normalize '(- (pow x 4) 1)) '(sub (pow x 4) 1))
  (check "denote sub" (denote '(- x x) '((x . 5))) 0)
  (check "denote pow" (denote '(pow x 2) '((x . 3))) 9)
  (check "sexp->xml" (sexp->xml '(vanish (- x x)))
         "<vanish><expr><sub><expr><symbol>x</symbol></expr><expr><symbol>x</symbol></expr></sub></expr></vanish>")
  (check "sexp->openmath" (sexp->openmath '(vanish (- x x)))
         "<OMOBJ><OMA><OMS cd=\"vanish1\" name=\"vanishes\"/><OMA><OMS cd=\"arith1\" name=\"minus\"/><OMV name=\"x\"/><OMV name=\"x\"/></OMA></OMA></OMOBJ>")
  (check "sexp->openmath quartic" (sexp->openmath '(- (pow x 4) 1))
         "<OMOBJ><OMA><OMS cd=\"arith1\" name=\"minus\"/><OMA><OMS cd=\"arith1\" name=\"power\"/><OMV name=\"x\"/><OMI>4</OMI></OMA><OMI>1</OMI></OMA></OMOBJ>")
  (if (zero? failures)
      (begin (printf "SELFTEST PASS\n") 0)
      (begin (printf "SELFTEST FAIL: ~a failures\n" failures) 1)))

(module+ main
  (define args (current-command-line-arguments))
  (cond
    ((and (= (vector-length args) 1) (equal? (vector-ref args 0) "--selftest"))
     (exit (selftest)))
    ((and (= (vector-length args) 3) (equal? (vector-ref args 0) "--xml"))
     (let ((expr (read-sexp-file (vector-ref args 1))))
       (call-with-output-file (vector-ref args 2) #:exists 'replace
         (lambda (out) (display (sexp->xml expr) out)))))
    ((and (= (vector-length args) 3) (equal? (vector-ref args 0) "--openmath"))
     (let ((expr (read-sexp-file (vector-ref args 1))))
       (call-with-output-file (vector-ref args 2) #:exists 'replace
         (lambda (out) (display (sexp->openmath expr) out)))))
    ((and (= (vector-length args) 2) (equal? (vector-ref args 0) "--normalize"))
     (let ((expr (read-sexp-file (vector-ref args 1))))
       (displayln (vanish-normalize expr))))
    (else
     (eprintf "usage: vanish.rkt --xml in.sexp out.xml | --openmath in.sexp out.om | --normalize in.sexp | --selftest\n")
     (exit 2))))
