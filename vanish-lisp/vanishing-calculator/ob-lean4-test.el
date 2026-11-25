;; VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published
;; by the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; See the LICENSE file for the full text.

;;; ob-lean4-test.el --- End-to-end test for ob-lean4.el  -*- lexical-binding: t; -*-

;; Run with: emacs --batch -l ob-lean4-test.el
;; Needs `lean' on PATH (elan bin).  Prints one marker line per check;
;; verify.py reads them.  The load-path entry is the directory holding
;; this file, which is also the directory holding ob-lean4.el.

(require 'org)
(add-to-list 'load-path (file-name-directory (or load-file-name (buffer-file-name))))
(load "ob-lean4")

(princ (format "EXEC1: %S\n"
               (org-babel-execute:lean4 "#eval 1 + 1\n#check Nat\ndef foo : Nat := 42\n#eval foo"
                                        '((:results . "output") (:exports . "both")))))
(princ (format "EXEC-ERR: %S\n"
               (org-babel-execute:lean4 "def bad : Nat := \"x\""
                                        '((:results . "output")))))
(princ (format "GENLINES: %S\n"
               (org-babel-lean4--generated-lines '((:prologue . "def p : Nat := 1")))))
(princ (format "LAKEP: %S %S\n"
               (org-babel-lean4--lake-p '((:lake . "yes")))
               (org-babel-lean4--lake-p '((:lake . "no")))))
(princ (format "TOOLCHAIN: %S\n" (org-babel-lean4--toolchain)))

;; Session across two different buffers, so the two blocks have different keys.
(let ((b1 (generate-new-buffer "sess1.org"))
      (b2 (generate-new-buffer "sess2.org")))
  (with-current-buffer b1
    (org-mode)
    (insert "#+begin_src lean4 :session t\ndef sessval : Nat := 7\n#+end_src\n")
    (goto-char (point-min))
    (search-forward "def sessval")
    (princ (format "SESS1: %S\n"
                   (org-babel-execute:lean4 "def sessval : Nat := 7"
                                            '((:session . "t") (:results . "output"))))))
  (with-current-buffer b2
    (org-mode)
    (insert "#+begin_src lean4 :session t\n#eval sessval + 1\n#+end_src\n")
    (goto-char (point-min))
    (search-forward "#eval")
    (princ (format "SESS2: %S\n"
                   (org-babel-execute:lean4 "#eval sessval + 1"
                                            '((:session . "t") (:results . "output"))))))
  ;; Re-running the first block must not replay its own earlier chunk.
  (with-current-buffer b1
    (goto-char (point-min))
    (search-forward "def sessval")
    (princ (format "SESS1-AGAIN: %S\n"
                   (org-babel-execute:lean4 "def sessval : Nat := 7"
                                            '((:session . "t") (:results . "output")))))))

;; Edit flow: open a real org file, edit its block, write back.
(let ((orgfile "/tmp/vc-test/oblean4/edit.org"))
  (make-directory (file-name-directory orgfile) t)
  (with-temp-file orgfile
    (insert "* Test\n\n#+begin_src lean4 :session ed :var n=3\n#eval n + 1\n#+end_src\n"))
  (find-file orgfile)
  (org-mode)
  (goto-char (point-min))
  (search-forward "#eval")
  (condition-case e
      (progn
        (org-babel-lean4-edit)
        (princ (format "EDIT-BUF: %S\n" (buffer-name)))
        (princ (format "EDIT-CONTENTS: %S\n" (buffer-substring-no-properties (point-min) (point-max))))
        (goto-char (point-min))
        (search-forward "#eval n + 1")
        (replace-match "#eval n + 2")
        (org-babel-lean4-edit-exit)
        (princ (format "ORG-AFTER-EDIT: %S\n" (buffer-substring-no-properties (point-min) (point-max)))))
    (error (princ (format "EDIT-ERROR: %S\n" e)))))

(kill-emacs 0)

;;; ob-lean4-test.el ends here
