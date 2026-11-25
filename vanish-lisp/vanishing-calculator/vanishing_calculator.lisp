;;;; Self-Modifying Vanishing Calculator (Common Lisp - pure)
;;;; STATE: VISIBLE
;;;; Load / run with: sbcl --script vanishing_calculator.lisp
;;;; or: clisp vanishing_calculator.lisp (etc.)

(defparameter *script-path*
  (or *load-truename*
      (error "Cannot determine script path")))

;; ============ CALCULATION ENGINE START ============
(defun calc-fibonacci (n)
  (cond ((<= n 0) "[]")
        ((= n 1) "[0]")
        (t
         (let ((a 0) (b 1) (result "[0, 1"))
           (loop for i from 2 below n
                 do (let ((c (+ a b)))
                      (setf result (format nil "~A, ~A" result c)
                            a b
                            b c)))
           (concatenate 'string result "]")))))

(defun calc-primes (limit)
  (if (< limit 2)
      "[]"
      (let ((sieve (make-array (1+ limit) :initial-element t)))
        (setf (aref sieve 0) nil
              (aref sieve 1) nil)
        (loop for i from 2 to (isqrt limit)
              when (aref sieve i)
              do (loop for j from (* i i) to limit by i
                       do (setf (aref sieve j) nil)))
        (let ((primes
               (loop for i from 2 to limit
                     when (aref sieve i) collect i)))
          (format nil "[~{~A~^, ~}]" primes)))))

;; FIXED (Muse 2026-11-23): the pasted LOOP form returned NIL for 0/1 and
;; 60 for 5 on SBCL 2.2.9 (measured). Replaced with the same loop the other
;; kernels use. Original line kept in STATUS.md.
(defun calc-factorial (n)
  (if (< n 0)
      "null"
      (let ((acc 1))
        (loop for i from 2 to n do (setf acc (* acc i)))
        acc)))
;; ============ CALCULATION ENGINE END ============

(defun base64-encode (string)
  "Minimal pure base64 encoder (no external libraries)."
  (let* ((alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
         (bytes (map 'vector #'char-code string))
         (len (length bytes))
         (out (make-array (* 4 (ceiling len 3)) :element-type 'character :fill-pointer 0)))
    (loop for i from 0 below len by 3
          do (let* ((b0 (aref bytes i))
                    (b1 (if (< (+ i 1) len) (aref bytes (+ i 1)) 0))
                    (b2 (if (< (+ i 2) len) (aref bytes (+ i 2)) 0))
                    (n (logior (ash b0 16) (ash b1 8) b2)))
               (vector-push (char alphabet (ldb (byte 6 18) n)) out)
               (vector-push (char alphabet (ldb (byte 6 12) n)) out)
               (vector-push (if (< (+ i 1) len)
                                (char alphabet (ldb (byte 6 6) n))
                                #\=)
                            out)
               (vector-push (if (< (+ i 2) len)
                                (char alphabet (ldb (byte 6 0) n))
                                #\=)
                            out)))
    (coerce out 'string)))

(defun base64-decode (string)
  "Minimal pure base64 decoder."
  (let* ((alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
         (table (make-array 128 :initial-element -1))
         (clean (remove-if (lambda (c) (or (char= c #\=) (char= c #\Newline) (char= c #\Return)))
                           string)))
    (loop for i from 0 below 64
          do (setf (aref table (char-code (char alphabet i))) i))
    (let* ((len (length clean))
           (out (make-array (* 3 (ceiling len 4)) :element-type 'character :fill-pointer 0)))
      (loop for i from 0 below len by 4
            do (let* ((c0 (aref table (char-code (char clean i))))
                      (c1 (aref table (char-code (char clean (+ i 1)))))
                      (c2 (if (< (+ i 2) len) (aref table (char-code (char clean (+ i 2)))) 0))
                      (c3 (if (< (+ i 3) len) (aref table (char-code (char clean (+ i 3)))) 0))
                      (n (logior (ash c0 18) (ash c1 12) (ash c2 6) c3)))
                 (vector-push (code-char (ldb (byte 8 16) n)) out)
                 (when (< (+ i 2) len)
                   (vector-push (code-char (ldb (byte 8 8) n)) out))
                 (when (< (+ i 3) len)
                   (vector-push (code-char (ldb (byte 8 0) n)) out))))
      (coerce out 'string))))

;; RECONSTRUCTED (Muse 2026-11-23): make-hidden / make-visible / main were
;; cut off in the paste at make-hidden; completed from the PowerShell/Racket
;; pattern in the same paste, using SEARCH/SUBSEQ.
(defun read-file-string (path)
  (with-open-file (s path :direction :input :external-format :utf-8)
    (let ((out (make-string-output-stream)))
      (loop for c = (read-char s nil nil) while c do (write-char c out))
      (get-output-stream-string out))))

(defun write-file-string (path string)
  (with-open-file (s path :direction :output :if-exists :supersede
                        :external-format :utf-8)
    (write-string string s)))

(defun str-replace-once (string old new)
  (let ((pos (search old string)))
    (if pos
        (concatenate 'string (subseq string 0 pos) new (subseq string (+ pos (length old))))
        string)))

(defun make-hidden ()
  (let* ((content (read-file-string *script-path*))
         (start-marker ";; ============ CALCULATION ENGINE START ============")
         (end-marker ";; ============ CALCULATION ENGINE END ============")
         (start-idx (search start-marker content))
         (end-idx (search end-marker content)))
    (unless (and start-idx end-idx)
      (error "Could not find markers"))
    (let* ((before (subseq content 0 (+ start-idx (length start-marker))))
           (hidden-section (subseq content (+ start-idx (length start-marker)) end-idx))
           (after (subseq content end-idx))
           (encoded (base64-encode hidden-section))
           (new-content (concatenate 'string before
                                     (format nil "~%;; [ENGINE HIDDEN - Run again to restore]~%")
                                     (format nil "(defparameter *hidden-payload* \"~A\")~%" encoded)
                                     after)))
      (setf new-content (str-replace-once new-content ";;;; STATE: VISIBLE" ";;;; STATE: HIDDEN"))
      (write-file-string *script-path* new-content)
      (format t "~%[~C] Rewrote: ~A~%" #\✓ *script-path*))))

(defun make-visible ()
  (let* ((content (read-file-string *script-path*))
         (payload-start (search "(defparameter *hidden-payload* \"" content)))
    (unless payload-start
      (error "No hidden payload found"))
    (let* ((enc-start (+ payload-start (length "(defparameter *hidden-payload* \"")))
           (enc-end (position #\" content :start enc-start))
           (encoded (subseq content enc-start enc-end))
           (decoded (base64-decode encoded))
           (start-marker ";; ============ CALCULATION ENGINE START ============")
           (end-marker ";; ============ CALCULATION ENGINE END ============")
           (start-idx (search start-marker content))
           (end-idx (search end-marker content)))
      (unless (and start-idx end-idx)
        (error "Could not find markers"))
      (let* ((before (subseq content 0 (+ start-idx (length start-marker))))
             (after (subseq content end-idx))
             (new-content (concatenate 'string before decoded after)))
        (setf new-content (str-replace-once new-content ";;;; STATE: HIDDEN" ";;;; STATE: VISIBLE"))
        ;; FIXED (Muse 2026-11-23): no separate payload removal. The payload
        ;; sat between the markers, so before+decoded+after already excludes
        ;; it. Searching the whole restored file for the payload pattern
        ;; would match the pattern string inside make-hidden itself.
        (write-file-string *script-path* new-content)
        (format t "~%[~C] Rewrote: ~A~%" #\✓ *script-path*)))))

(defun main ()
  (let ((content (read-file-string *script-path*)))
    (format t "=======================================================~%")
    (format t " SELF-MODIFYING VANISHING CALCULATOR (COMMON LISP)~%")
    (format t "=======================================================~%")
    ;; FIXED (Muse 2026-11-23): a whole-file SEARCH always hits, because the
    ;; toggle code itself contains ";;;; STATE: VISIBLE". Require the newline
    ;; before it, so only the header line matches.
    (if (search (format nil "~%;;;; STATE: VISIBLE") content)
        (progn
          (format t "~%STATE: VISIBLE - Calculation Engine is ACTIVE~%~%")
          (format t "Fibonacci(10): ~A~%" (calc-fibonacci 10))
          (format t "Primes(30): ~A~%" (calc-primes 30))
          (format t "Factorial(5): ~A~%" (calc-factorial 5))
          (make-hidden)
          ;; FIXED (Muse 2026-11-23): SBCL --script keeps the file open and
          ;; tries to read past (main) after it returns; the file was just
          ;; rewritten under it, so the loader re-reads at a stale offset
          ;; and dies with a READ error at EOF. Exit at once after rewriting.
          (sb-ext:exit :code 0))
        (progn
          (format t "~%STATE: HIDDEN - Calculation Engine is HIDDEN~%")
          (make-visible)
          (format t "Engine restored. Run again to calculate.~%")
          (sb-ext:exit :code 0)))))

(main)
