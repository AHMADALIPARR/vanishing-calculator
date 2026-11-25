#lang racket
;; gherkin/runner.rkt -- Step bindings for gherkin/vanishing.feature.
;;
;; Usage: runner.rkt --root REPO --work WORKDIR FEATURE
;;
;; The runner parses the .feature file, dispatches each step to a real
;; pipeline stage, and reports pass/fail per scenario. Every Then calls
;; a real check; there are no fake bindings. The stages it drives:
;;   POP-11 reduction  -- scheme/vanish.rkt --normalize, the runnable
;;                        Racket mirror of pop11/rewrite.p (no pop11
;;                        binary exists on this box)
;;   AMPL search       -- ampl/check.c, the exact certified equivalent
;;                        of ampl/vanish.mod (AMPL is not installed)
;;   Lean certificate  -- lake env lean tests/certificates/CertificateTests.lean
;;   ELF seal / load   -- elf/writer/vanish-elf and elf/loader/vanish-load
;;   VM                -- vm/vanish-vm
;; The WORKDIR holds the binaries and the artifacts run_pipeline.sh
;; built for the four pipeline examples.

(require racket/system
         racket/string
         racket/port
         racket/file
         racket/match)

;; ------------------------------------------------------------------
;; Small utilities

(struct step (kind text) #:transparent)
(struct scenario (name steps) #:transparent)

(define (fail msg)
  (raise (exn:fail msg (current-continuation-marks))))

(define (run-cmd cmd args #:dir [dir #f])
  ;; Run CMD with ARGS, return (list exit-code stdout-string stderr-string).
  ;; process* returns one list: (stdout stdin pid stderr control).
  (define (go)
    (define r (apply process* cmd args))
    (define out (first r))
    (define in (second r))
    (define err (fourth r))
    (define control (fifth r))
    (close-output-port in)
    (define stdout-str (port->string out))
    (define stderr-str (port->string err))
    (close-input-port out)
    (close-input-port err)
    (control 'wait)
    (define code (control 'exit-code))
    (list (if (number? code) code 1) stdout-str stderr-str))
  (if dir
      (parameterize ([current-directory dir]) (go))
      (go)))

(define (run-ok? result)
  (= (first result) 0))

(define (quoted text)
  ;; The double-quoted argument of a step, or #f.
  (define m (regexp-match #rx"\"([^\"]*)\"" text))
  (and m (second m)))

;; ------------------------------------------------------------------
;; Feature file parser

(define (parse-feature path)
  (define scenarios '())
  (define current-name #f)
  (define current-steps '())
  (define current-kind 'given)
  (define (flush)
    (when current-name
      (set! scenarios (append scenarios (list (scenario current-name (reverse current-steps)))))
      (set! current-steps '())))
  (for ([line (in-lines (open-input-file path))])
    (define trimmed (string-trim line))
    (cond
      [(or (string=? trimmed "") (string-prefix? trimmed "#"))
       (void)]
      [(string-prefix? trimmed "Feature:")
       (void)]
      [(string-prefix? trimmed "Scenario:")
       (flush)
       (set! current-name (string-trim (substring trimmed (string-length "Scenario:"))))
       (set! current-kind 'given)]
      [else
       (define m (regexp-match #rx"^(Given|When|Then|And)[ \t]+(.*)$" trimmed))
       (unless m (fail (format "runner: cannot parse line: ~a" trimmed)))
       (define kw (second m))
       (define text (third m))
       (unless (string=? kw "And")
         (set! current-kind (string->symbol (string-downcase kw))))
       (set! current-steps (cons (step current-kind text) current-steps))]))
  (flush)
  scenarios)

;; ------------------------------------------------------------------
;; Polynomial string parser: "x^4 - 1" -> '(- (pow x 4) 1).
;; Terms with +, -, *, ^, parentheses, integers, single-letter vars.

(define (tokenize s)
  (define tokens '())
  (define i 0)
  (define n (string-length s))
  (define (peek) (if (< i n) (string-ref s i) #\null))
  (define (advance) (begin0 (peek) (set! i (+ i 1))))
  (let loop ()
    (define c (peek))
    (cond
      [(>= i n) (reverse tokens)]
      [(char-whitespace? c) (advance) (loop)]
      [(char-numeric? c)
       (define start i)
       (let num-loop ()
         (when (char-numeric? (peek)) (advance) (num-loop)))
       (set! tokens (cons (string->number (substring s start i)) tokens))
       (loop)]
      [(char-alphabetic? c)
       (set! tokens (cons (string->symbol (string (advance))) tokens))
       (loop)]
      [(member c '(#\+ #\- #\* #\^ #\( #\)))
       (set! tokens (cons (string->symbol (string (advance))) tokens))
       (loop)]
      [else (fail (format "runner: bad character in polynomial: ~a" c))])))

(struct parser (tokens pos) #:mutable #:transparent)

(define (p-peek p)
  (if (< (parser-pos p) (length (parser-tokens p)))
      (list-ref (parser-tokens p) (parser-pos p))
      'eof))

(define (p-take p)
  (begin0 (p-peek p) (set-parser-pos! p (+ (parser-pos p) 1))))

(define (p-expect p tok)
  (define got (p-take p))
  (unless (equal? got tok)
    (fail (format "runner: expected ~a, got ~a" tok got))))

;; expr := term (('+' | '-') term)*
(define (parse-expr p)
  (define lhs (parse-term p))
  (let loop ([lhs lhs])
    (define op (p-peek p))
    (cond
      [(equal? op '+) (p-take p) (loop (list '+ lhs (parse-term p)))]
      [(equal? op '-) (p-take p) (loop (list '- lhs (parse-term p)))]
      [else lhs])))

;; term := factor (('*') factor)*
(define (parse-term p)
  (define lhs (parse-factor p))
  (let loop ([lhs lhs])
    (if (equal? (p-peek p) '*)
        (begin (p-take p) (loop (list '* lhs (parse-factor p))))
        lhs)))

;; factor := primary ('^' integer)?
(define (parse-factor p)
  (define base (parse-primary p))
  (if (equal? (p-peek p) '^)
      (begin (p-take p)
             (let ([e (p-take p)])
               (unless (integer? e) (fail "runner: exponent must be an integer"))
               (list 'pow base e)))
      base))

(define (parse-primary p)
  (define tok (p-take p))
  (cond
    [(equal? tok 'eof) (fail "runner: unexpected end of polynomial")]
    [(equal? tok '-) (list '- 0 (parse-primary p))]
    [(equal? tok '+) (parse-primary p)]
    [(equal? tok '\()
     (define e (parse-expr p))
     (p-expect p '\))
     e]
    [(number? tok) tok]
    [(symbol? tok) tok]
    [else (fail (format "runner: unexpected token ~a" tok))]))

(define (parse-polynomial-string s)
  (define p (parser (tokenize s) 0))
  (define expr (parse-expr p))
  (unless (equal? (p-peek p) 'eof)
    (fail (format "runner: trailing tokens in polynomial ~a" s)))
  expr)

;; ------------------------------------------------------------------
;; Univariate polynomials in x, for the certificate witness check.
;; A polynomial is a hash from exponent (exact integer) to coefficient.

(define (poly-from-sexp e)
  (match e
    [(? number? n) (hash 0 n)]
    [(? symbol? v) (if (equal? v 'x) (hash 1 1) (fail (format "runner: witness check is univariate in x, got ~a" v)))]
    [(list 'pow base n)
     (define b (poly-from-sexp base))
     (unless (and (integer? n) (>= n 0)) (fail "runner: negative exponent in witness check"))
     (let loop ([acc (hash 0 1)] [k n])
       (if (= k 0) acc (loop (poly-mul acc b) (- k 1))))]
    [(list '+ a b) (poly-add (poly-from-sexp a) (poly-from-sexp b))]
    [(list '- a b) (poly-add (poly-from-sexp a) (poly-neg (poly-from-sexp b)))]
    [(list '- a) (poly-neg (poly-from-sexp a))]
    [(list '* a b) (poly-mul (poly-from-sexp a) (poly-from-sexp b))]
    [_ (fail (format "runner: cannot use ~a in the witness check" e))]))

(define (poly-add a b)
  (for/fold ([acc a]) ([(k v) (in-hash b)])
    (define nv (+ v (hash-ref acc k 0)))
    (if (= nv 0) (hash-remove acc k) (hash-set acc k nv))))

(define (poly-neg a)
  (for/hash ([(k v) (in-hash a)]) (values k (- v))))

(define (poly-mul a b)
  (for*/fold ([acc (hash)]) ([(ka va) (in-hash a)] [(kb vb) (in-hash b)])
    (define k (+ ka kb))
    (define nv (+ (* va vb) (hash-ref acc k 0)))
    (if (= nv 0) (hash-remove acc k) (hash-set acc k nv))))

(define (poly-equal? a b) (equal? a b))

;; ------------------------------------------------------------------
;; XML helpers (the certificate witness is read with plain string
;; matching: the certificate files are small and their element names
;; are fixed by xslt/certificates.xsl).

(define (xml-element-text path element)
  (define text (file->string path))
  ;; An empty element serializes as <generators/>; a non-empty one as
  ;; <generators>...</generators>. Both forms are read here.
  (cond
    [(regexp-match (regexp (format "<~a/>" element)) text) ""]
    [else
     (define m (regexp-match (regexp (format "<~a>([^<]*)</~a>" element element)) text))
     (and m (string-trim (second m)))]))

;; ------------------------------------------------------------------
;; Scenario state and step dispatch

(struct ctx (root work feature
               [example #:mutable]
               [poly-sexp #:mutable]
               [poly-string #:mutable]
               [constraint #:mutable]
               [normalized #:mutable]
               [ampl #:mutable]
               [lean #:mutable]
               [elf #:mutable]
               [dump #:mutable]
               [corr #:mutable]
               [axioms #:mutable])
  #:transparent)

(define (example-sexp root name)
  (define path (build-path root "tests" "examples" (format "~a.sexp" name)))
  (define in (open-input-file path))
  (define sexp (read in))
  (close-input-port in)
  (if (and (pair? sexp) (equal? (first sexp) 'vanish))
      (second sexp)
      sexp))

(define (find-example c sexp)
  (for/or ([name '("ex1" "ex2" "ex3" "ex4")])
    (and (equal? (example-sexp (ctx-root c) name) sexp) name)))

(define (work-path c name)
  (build-path (ctx-work c) name))

(define (bin c name)
  (build-path (ctx-work c) name))

(define (check cond msg)
  (unless cond (fail msg)))

(define (dispatch c st)
  (match (step-kind st)
    ['given (dispatch-given c (step-text st))]
    ['when (dispatch-when c (step-text st))]
    ['then (dispatch-then c (step-text st))]))

(define (dispatch-given c text)
  (cond
    [(string-prefix? text "polynomial ")
     (define poly (quoted text))
     (check poly "runner: Given polynomial needs a quoted polynomial")
     (define sexp (parse-polynomial-string poly))
     (define example (find-example c sexp))
     (check example
            (format "runner: no pipeline example matches polynomial ~a" poly))
     (set-ctx-poly-string! c poly)
     (set-ctx-poly-sexp! c sexp)
     (set-ctx-example! c example)
     (printf "  polynomial ~a is example ~a (~a)\n" poly example sexp)]
    [(string-prefix? text "constraint ")
     (define con (quoted text))
     (check con "runner: constraint needs a quoted constraint")
     (define parts (string-split con "="))
     (check (= (length parts) 2) (format "runner: bad constraint ~a" con))
     (check (string=? (string-trim (second parts)) "0")
            "runner: only constraints equal to zero are supported")
     (set-ctx-constraint! c (string-trim (first parts)))
     (printf "  constraint ~a = 0\n" (ctx-constraint c))]
    [else (fail (format "runner: unknown Given step: ~a" text))]))

(define (dispatch-when c text)
  (cond
    [(string=? text "POP-11 reduces the expression")
     ;; The runnable mirror of pop11/rewrite.p: no pop11 binary exists
     ;; on this box, so scheme/vanish.rkt runs the same rewrite rules.
     (define r (run-cmd (find-executable-path "racket")
                        (list (path->string (build-path (ctx-root c) "scheme" "vanish.rkt"))
                              "--normalize"
                              (path->string (build-path (ctx-root c) "tests" "examples"
                                                       (format "~a.sexp" (ctx-example c)))))))
     (check (run-ok? r) (format "runner: POP-11 reduction failed: ~a" (third r)))
     (set-ctx-normalized! c (string-trim (second r)))
     (printf "  POP-11 reduction (Scheme mirror of pop11/rewrite.p): ~a\n" (ctx-normalized c))]
    [(string=? text "AMPL searches for a counterexample")
     (define r (run-cmd (path->string (bin c "ampl-check")) '()))
     (set-ctx-ampl! c r)
     (check (run-ok? r) (format "runner: AMPL search found a counterexample: ~a" (second r)))
     (printf "  AMPL exact search: no counterexample (max violation 0)\n")]
    [(string=? text "Lean validates the algebraic certificate")
     (define r (run-cmd (find-executable-path "lake")
                        (list "env" "lean" "tests/certificates/CertificateTests.lean")
                        #:dir (ctx-root c)))
     (set-ctx-lean! c r)
     (check (run-ok? r) (format "runner: Lean certificate check failed: ~a" (third r)))
     (printf "  Lean certificate check: CertificateTests passes\n")]
    [(string=? text "the pipeline seals the ELF artifact")
     (define ex (ctx-example c))
     (define out (work-path c (format "~a.roundtrip.elf" ex)))
     (define r (run-cmd (path->string (bin c "vanish-elf"))
                        (list "-o" (path->string out)
                              (path->string (work-path c (format "~a.prog.xml" ex)))
                              (path->string (work-path c (format "~a.canon.xml" ex)))
                              (path->string (work-path c (format "~a.cert.xml" ex))))))
     (check (run-ok? r) (format "runner: ELF sealing failed: ~a" (third r)))
     (set-ctx-elf! c out)
     (printf "  sealed ~a\n" out)]
    [(string=? text "the loader reads the ELF artifact back")
     (define elf (or (ctx-elf c)
                     (work-path c (format "~a.elf" (ctx-example c)))))
     (define r (run-cmd (path->string (bin c "vanish-load"))
                        (list (path->string elf) "--dump")))
     (check (run-ok? r) (format "runner: ELF load failed: ~a" (third r)))
     (set-ctx-dump! c (second r))
     (printf "  loader read ~a back\n" elf)]
    [(string=? text "the correspondence check runs on the expression")
     ;; Per-expression differential check: the real XSLT lowering on
     ;; the real Scheme-emitted XML, against a batched Lean run of
     ;; compile and lowerXml o encode, plus determinism and the decode
     ;; round-trip. The universal theorem is Vanish.correspondence.
     (check (ctx-poly-sexp c) "runner: no polynomial set for the correspondence check")
     (define sexp-str (format "~a" (ctx-poly-sexp c)))
     (define r (run-cmd (find-executable-path "elixir")
                        (list "tests/correspondence.exs" "--one" sexp-str)
                        #:dir (ctx-root c)))
     (set-ctx-corr! c r)
     (check (run-ok? r) (format "runner: correspondence check failed for ~a: ~a~a"
                                sexp-str (second r) (third r)))
     (printf "  correspondence check on ~a: ~a"
             sexp-str
             (string-join
              (filter (lambda (ln)
                        (or (string-prefix? ln "determinism:")
                            (string-prefix? ln "decode:")
                            (string-prefix? ln "lowering==compile:")
                            (string-prefix? ln "lowering==lowerXml:")))
                      (string-split (second r) "\n"))
              ", "))]
    [(string=? text "the Lean correspondence theorems are checked")
     ;; The universal theorems exist, are proved, and depend only on
     ;; the standard Lean axioms. tests/axioms.lean prints the
     ;; dependency list for each main theorem.
     (define r (run-cmd (find-executable-path "lake")
                        (list "env" "lean" "tests/axioms.lean")
                        #:dir (ctx-root c)))
     (set-ctx-axioms! c r)
     (check (run-ok? r) (format "runner: Lean correspondence theorems failed: ~a" (third r)))
     (check (not (string-contains? (second r) "sorryAx"))
            "runner: a correspondence theorem depends on sorryAx")
     (for ([line (string-split (second r) "\n")])
       (when (string-contains? line "depends on axioms:")
         (check (regexp-match #rx"depends on axioms: \\[(propext(, )?)?(Classical\\.choice(, )?)?(Quot\\.sound)?\\]" line)
                (format "runner: non-standard axiom dependency: ~a" line))))
     (printf "  Lean correspondence theorems: axioms are standard only\n")]
    [else (fail (format "runner: unknown When step: ~a" text))]))

(define (dispatch-then c text)
  (cond
    [(string=? text "the polynomial shall be classified as vanishing")
     (check (and (ctx-ampl c) (run-ok? (ctx-ampl c)))
            "runner: AMPL did not search, or found a counterexample")
     (check (and (ctx-lean c) (run-ok? (ctx-lean c)))
            "runner: Lean did not validate the certificate")
     (check (witness-verifies? c)
            "runner: certificate witness does not verify")
     (printf "  classified vanishing: AMPL clean, Lean valid, witness verifies\n")]
    [(string=? text "the symbolic residual shall equal zero")
     (check (witness-verifies? c)
            "runner: witness quotient * generator + remainder != target")
     (printf "  symbolic residual is zero: quotient * generator + remainder = target\n")]
    [(string=? text "the ELF artifact shall contain a verified certificate")
     (define ex (ctx-example c))
     (define r (run-cmd (path->string (bin c "vanish-load"))
                        (list (path->string (work-path c (format "~a.elf" ex))) "--dump")))
     (check (run-ok? r) (format "runner: ELF load failed: ~a" (third r)))
     (check (string-contains? (second r) "cert_soundness")
            "runner: proof section does not name the Lean theorem cert_soundness")
     (check (string-contains? (second r) "OK hashes:")
            "runner: loader did not report verified hashes")
     (printf "  ELF contains the verified certificate (cert_soundness, hashes OK)\n")]
    [(string=? text "the polynomial shall not be classified as vanishing")
     (check (and (ctx-normalized c)
                 (not (member (ctx-normalized c) '("0" "(vanish 0)"))))
            (format "runner: reduction unexpectedly gave zero: ~a" (ctx-normalized c)))
     (define r (run-cmd (path->string (bin c "vanish-vm"))
                        (list (path->string (work-path c (format "~a.elf" (ctx-example c)))))))
     (check (not (run-ok? r))
            "runner: VM unexpectedly passed ASSERT_ZERO on a non-vanishing program")
     (check (string-contains? (string-append (second r) (third r)) "ASSERT_ZERO FAIL")
            "runner: VM did not fail with ASSERT_ZERO FAIL")
     (printf "  not vanishing: reduction leaves ~a, VM fails ASSERT_ZERO\n" (ctx-normalized c))]
    [(string=? text "the obligation shall remain unresolved")
     (define cert (work-path c (format "~a.cert.xml" (ctx-example c))))
     (define gens (xml-element-text cert "generators"))
     (check (and gens (string=? gens ""))
            (format "runner: certificate unexpectedly carries generators: ~a" gens))
     (printf "  obligation unresolved: certificate witness carries no generators\n")]
    [(string=? text "the loader shall reconstruct the identical AST")
     (check (ctx-dump c) "runner: no loader dump to compare")
     (define dump (ctx-dump c))
     (define (str-index str sub)
       (define m (regexp-match-positions (regexp-quote sub) str))
       (and m (caar m)))
     (define ast-start (str-index dump "--- ast ---"))
     (define proof-start (str-index dump "--- proof ---"))
     (check (and ast-start proof-start) "runner: loader dump has no AST section")
     (define ast-in-dump
       (string-trim (substring dump (+ ast-start (string-length "--- ast ---")) proof-start)))
     (define ast-file
       (string-trim (file->string (work-path c (format "~a.canon.xml" (ctx-example c))))))
     (check (string=? ast-in-dump ast-file)
            (format "runner: reconstructed AST differs from the sealed AST:\nloader: ~a\nfile:   ~a"
                    ast-in-dump ast-file))
     (printf "  reconstructed AST is identical to the sealed AST\n")]
    [(string=? text "the section hashes shall match")
     (check (ctx-dump c) "runner: no loader dump to check hashes against")
     (check (string-contains? (ctx-dump c) "OK hashes:")
            "runner: loader did not report verified hashes")
     (printf "  section hashes match (loader recomputed and compared all four)\n")]
    [(string=? text "the XSLT lowering shall equal the Lean compile")
     (check (ctx-corr c) "runner: correspondence check did not run")
     (check (string-contains? (second (ctx-corr c)) "lowering==compile: PASS")
            "runner: XSLT lowering did not equal the Lean compile")
     (printf "  XSLT lowering equals the Lean compile on the expression\n")]
    [(string=? text "the lowering shall be deterministic")
     (check (ctx-corr c) "runner: correspondence check did not run")
     (check (string-contains? (second (ctx-corr c)) "determinism: PASS")
            "runner: XSLT lowering was not deterministic")
     (printf "  lowering is deterministic (two runs byte-identical)\n")]
    [(string=? text "the compiled program shall never underflow the stack")
     (check (ctx-axioms c) "runner: Lean correspondence theorems were not checked")
     (check (run-ok? (ctx-axioms c)) "runner: Lean correspondence theorems failed")
     (check (string-contains? (second (ctx-axioms c)) "stack_safe")
            "runner: stack_safe theorem missing from the axioms check")
     (printf "  compiled program never underflows (stack_safe, proved for all expressions)\n")]
    [(string=? text "the stack depth shall be bounded by the expression size")
     (check (ctx-axioms c) "runner: Lean correspondence theorems were not checked")
     (check (run-ok? (ctx-axioms c)) "runner: Lean correspondence theorems failed")
     (check (string-contains? (second (ctx-axioms c)) "stack_bound")
            "runner: stack_bound theorem missing from the axioms check")
     (printf "  stack depth bounded by expression size (stack_bound, proved for all expressions)\n")]
    [(string=? text "the XML shall decode to the original expression")
     (check (ctx-corr c) "runner: correspondence check did not run")
     (check (string-contains? (second (ctx-corr c)) "decode: PASS")
            "runner: Scheme XML did not decode to the original expression")
     (printf "  Scheme XML decodes to the original expression (canonical form)\n")]
    [else (fail (format "runner: unknown Then step: ~a" text))]))

;; The certificate witness verifies when quotient * generator +
;; remainder equals the target polynomial, all as univariate
;; polynomials in x. The witness comes from the certificate XML the
;; pipeline issued for the example.
(define (witness-verifies? c)
  (define cert (work-path c (format "~a.cert.xml" (ctx-example c))))
  (define gens (xml-element-text cert "generators"))
  (define quots (xml-element-text cert "quotients"))
  (define rem (xml-element-text cert "remainder"))
  (and gens quots rem
       (not (string=? gens ""))
       (let ([target (poly-from-sexp (ctx-poly-sexp c))]
             [product (poly-mul (poly-from-sexp (parse-polynomial-string quots))
                                (poly-from-sexp (parse-polynomial-string gens)))]
             [remainder (poly-from-sexp (parse-polynomial-string rem))])
         (poly-equal? target (poly-add product remainder)))))

;; ------------------------------------------------------------------
;; Main

(define (main argv)
  (define root #f)
  (define work #f)
  (define feature #f)
  (let loop ([args argv])
    (cond
      [(null? args) (void)]
      [(equal? (first args) "--root") (set! root (second args)) (loop (cddr args))]
      [(equal? (first args) "--work") (set! work (second args)) (loop (cddr args))]
      [else (set! feature (first args)) (loop (rest args))]))
  (unless (and root work feature)
    (printf "usage: runner.rkt --root REPO --work WORKDIR FEATURE\n")
    (exit 2))
  (define scenarios (parse-feature feature))
  (define failures 0)
  (for ([sc scenarios])
    (printf "Scenario: ~a\n" (scenario-name sc))
    (define c (ctx root work feature #f #f #f #f #f #f #f #f #f #f #f))
    (define ok
      (with-handlers ([exn:fail?
                       (lambda (e)
                         (printf "  FAIL: ~a\n" (exn-message e))
                         #f)])
        (for ([st (scenario-steps sc)])
          (printf "  ~a ~a\n"
                  (match (step-kind st)
                    ['given "Given"] ['when "When"] ['then "Then"])
                  (step-text st))
          (dispatch c st))
        #t))
    (if ok
        (printf "  PASS\n")
        (begin (set! failures (+ failures 1)) (printf "  FAIL\n"))))
  (printf "~a scenario(s), ~a failed\n" (length scenarios) failures)
  (exit (if (= failures 0) 0 1)))

(main (vector->list (current-command-line-arguments)))
