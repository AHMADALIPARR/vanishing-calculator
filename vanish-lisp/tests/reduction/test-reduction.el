;;; test-reduction.el --- ERT tests for VANISH-LISP reduction & constraints -*- lexical-binding: t; -*-

(require 'ert)
(require 'vanish)
(require 'macros)

(ert-deftest vl-test-basic-vanishing ()
  (should (equal (vanish (- x x)) 0))
  (should (equal (vanish (* 0 (+ x y))) 0))
  (should (equal (vanish (- (+ x 0) x)) 0))
  (should (equal (vanish (- (pow x 2) (* x x)))
                 '(- (pow x 2) (* x x)))))

(ert-deftest vl-test-normalize-nary-product ()
  "Regression: n-argument * drops 1s and folds integer constants."
  (should (equal (vl-normalize '(* 2 x 1)) '(* 2 x)))
  (should (equal (vl-normalize '(* 1 x)) 'x))
  (should (equal (vl-normalize '(* 2 3 x)) '(* 6 x)))
  (should (equal (vl-normalize '(* 0 x)) 0))
  (should (equal (vl-normalize '(* 2 3)) 6))
  (should (equal (vl-normalize '(* x y)) '(* x y))))

(ert-deftest vl-test-under-constraints ()
  (should (equal (vanish (under ((= x y)) (- x y))) 0)))

(ert-deftest vl-test-serialization ()
  (should (equal (vl-sexp-to-pop11 '(- x x)) "[sub x x]"))
  (should (equal (vl-sexp-to-pop11 '(* 0 (+ x y))) "[mul 0 [add x y]]"))
  (should (equal (vl-sexp-to-lean '(- (pow x 2) 1)) "((x ^ 2) - 1)")))

(provide 'test-reduction)
;;; test-reduction.el ends here
