;; VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published
;; by the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; See the LICENSE file for the full text.

;;; test-differential.el --- ERT tests for symbolic differentiation -*- lexical-binding: t; -*-

(require 'ert)
(require 'vanish)
(require 'macros)

(ert-deftest vl-test-derivative-vanishing ()
  (should (equal (vanish (derivative x (+ (* 0 x) 7))) 0))
  (should (equal (vanish (derivative x y)) 0))
  (should (equal (vanish (derivative x x)) 1))
  (should (equal (vanish (derivative x (pow x 2))) '(* 2 x))))

(provide 'test-differential)
;;; test-differential.el ends here
