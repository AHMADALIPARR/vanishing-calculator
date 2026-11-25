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
