#lang racket
;; scheme/batch-xml.rkt -- Batch S-expression to vanish XML emitter for
;; the correspondence corpus check (tests/correspondence.py).
;;
;; Reads one S-expression per line from stdin, writes one vanish XML
;; document per line to stdout, in the same order. One Racket process
;; for the whole corpus, so the corpus uses the real Scheme emitter
;; (scheme/vanish.rkt, `sexp->xml`) end to end, not a reimplementation.
;; Blank lines are skipped. A line that does not parse, or an
;; expression the emitter rejects, stops the run with a nonzero exit.
;;
;; Usage:
;;   racket batch-xml.rkt < exprs.sexp > exprs.xml

(require "vanish.rkt")

(module+ main
  (let loop ()
    (define line (read-line))
    (unless (eof-object? line)
      (when (non-empty-string? (string-trim line))
        (define expr (read (open-input-string line)))
        (displayln (sexp->xml expr)))
      (loop))))
