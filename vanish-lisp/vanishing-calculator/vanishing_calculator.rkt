#lang racket
;; Self-Modifying Vanishing Calculator (Racket)
;; STATE: VISIBLE
;; Run with: racket vanishing_calculator.rkt

;; RECONSTRUCTED (Muse 2026-11-23): requires + str-index helper + main tail.
;; string-contains? in Racket 8.15 returns #t/#f, not an index, so the pasted
;; make-hidden/make-visible could not locate the markers as written.
;; str-index below returns the index (or #f) via regexp-match-positions.
(require net/base64)
(require racket/string)
(require racket/file)

(define script-path
  (path->string (find-system-path 'run-file)))

;; FIXED (Muse 2026-11-23): Racket expands the whole module, so a direct
;; (calc-fibonacci ...) call in main fails to compile once the engine is
;; hidden. Main calls the engine through eval in the module namespace below,
;; so the hidden file still loads. Tested with a namespace-anchor probe.
(define-namespace-anchor anchor)
(define mod-ns (namespace-anchor->namespace anchor))

(define (str-index hay needle)
  (define m (regexp-match-positions (regexp-quote needle) hay))
  (if m (caar m) #f))

;; ============ CALCULATION ENGINE START ============
(define (calc-fibonacci n)
  (cond [(<= n 0) "[]"]
        [(= n 1) "[0]"]
        [else
         (let loop ([i 2] [a 0] [b 1] [acc "(0 1"])
           (if (>= i n)
               (string-append acc ")")
               (let ([c (+ a b)])
                 (loop (add1 i) b c
                       (string-append acc " " (number->string c))))))]))

(define (calc-primes limit)
  (if (< limit 2)
      "[]"
      (let* ([sieve (make-vector (add1 limit) #t)])
        (vector-set! sieve 0 #f)
        (vector-set! sieve 1 #f)
        (for ([i (in-range 2 (add1 (integer-sqrt limit)))])
          (when (vector-ref sieve i)
            (for ([j (in-range (* i i) (add1 limit) i)])
              (vector-set! sieve j #f))))
        (let ([primes
               (for/list ([i (in-range 2 (add1 limit))]
                          #:when (vector-ref sieve i))
                 i)])
          (string-append "(" (string-join (map number->string primes) " ") ")")))))

(define (calc-factorial n)
  (if (< n 0)
      "null"
      (let loop ([i 2] [acc 1])
        (if (> i n)
            acc
            (loop (add1 i) (* acc i))))))
;; ============ CALCULATION ENGINE END ============

(define (make-hidden)
  (define content (file->string script-path))
  (define start-marker ";; ============ CALCULATION ENGINE START ============")
  (define end-marker ";; ============ CALCULATION ENGINE END ============")
  (define start-idx (str-index content start-marker))
  (define end-idx (str-index content end-marker))
  (unless (and start-idx end-idx)
    (error "Could not find markers"))
  (define before (substring content 0 (+ start-idx (string-length start-marker))))
  (define hidden-section
    (substring content
               (+ start-idx (string-length start-marker))
               end-idx))
  (define after (substring content end-idx))
  (define encoded (bytes->string/utf-8 (base64-encode (string->bytes/utf-8 hidden-section) #"")))
  (define new-content
    (string-append before
                   "\n;; [ENGINE HIDDEN - Run again to restore]\n"
                   "(define HIDDEN-PAYLOAD \"" encoded "\")\n"
                   after))
  ;; FIXED (Muse 2026-11-23): string-replace is global and would also rewrite
  ;; the ";; STATE: VISIBLE" strings inside make-hidden/make-visible.
  ;; Anchor to the header line only; regexp-replace replaces the first match.
  (define new-content2
    (regexp-replace #rx"(?m:^;; STATE: VISIBLE)" new-content ";; STATE: HIDDEN"))
  (with-output-to-file script-path
    #:exists 'replace
    (lambda () (display new-content2)))
  (newline)
  (displayln (format "[✓] Rewrote: ~a" script-path)))

(define (make-visible)
  (define content (file->string script-path))
  (define m (regexp-match #px"\\(define HIDDEN-PAYLOAD \"([^\"]+)\"\\)" content))
  (unless m (error "No hidden payload found"))
  (define encoded (second m))
  (define decoded (bytes->string/utf-8 (base64-decode (string->bytes/utf-8 encoded))))
  (define start-marker ";; ============ CALCULATION ENGINE START ============")
  (define end-marker ";; ============ CALCULATION ENGINE END ============")
  (define start-idx (str-index content start-marker))
  (define end-idx (str-index content end-marker))
  (unless (and start-idx end-idx)
    (error "Could not find markers"))
  (define before (substring content 0 (+ start-idx (string-length start-marker))))
  (define after (substring content end-idx))
  (define new-content (string-append before decoded after))
  ;; FIXED (Muse 2026-11-23): same anchoring as make-hidden, and no separate
  ;; payload removal: the payload sat between the markers, so before+decoded
  ;; +after already excludes it. A whole-file payload regex would match the
  ;; (define HIDDEN-PAYLOAD ...) string inside make-hidden itself.
  (define new-content2
    (regexp-replace #rx"(?m:^;; STATE: HIDDEN)" new-content ";; STATE: VISIBLE"))
  (with-output-to-file script-path
    #:exists 'replace
    (lambda () (display new-content2)))
  (newline)
  (displayln (format "[✓] Rewrote: ~a" script-path)))

;; RECONSTRUCTED TAIL (Muse 2026-11-23): main body after the banner was cut off in the paste.
(define (main)
  (define content (file->string script-path))
  (displayln "=======================================================")
  (displayln " SELF-MODIFYING VANISHING CALCULATOR (RACKET)")
  (displayln "=======================================================")
  ;; FIXED (Muse 2026-11-23): a whole-file string-contains? always hits,
  ;; because the toggle code itself contains ";; STATE: VISIBLE". Check for
  ;; the exact header line instead.
  (if (member ";; STATE: VISIBLE" (string-split content "\n"))
      (begin
        (newline)
        (displayln "STATE: VISIBLE - Calculation Engine is ACTIVE")
        (newline)
        (displayln (format "Fibonacci(10): ~a" (eval '(calc-fibonacci 10) mod-ns)))
        (displayln (format "Primes(30): ~a" (eval '(calc-primes 30) mod-ns)))
        (displayln (format "Factorial(5): ~a" (eval '(calc-factorial 5) mod-ns)))
        (make-hidden))
      (begin
        (newline)
        (displayln "STATE: HIDDEN - Calculation Engine is HIDDEN")
        (make-visible)
        (displayln "Engine restored. Run again to calculate."))))

(main)
