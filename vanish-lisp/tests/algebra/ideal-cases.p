;;; ideal-cases.p --- POP-11 ideal membership test cases
;;; SPDX-License-Identifier: MIT

load('../../pop11/vanish.p');

;;; Test: x^4 - 1 in <x^2 - 1>
vanish_eval([ideal [generators [sub [pow x 2] 1]] [sub [pow x 4] 1]]) =>

;;; Test: (x + 1)^2 - x^2 - 2x - 1 vanishes identically
vl_normalize_canon([sub [sub [sub [pow [add x 1] 2] [pow x 2]] [mul 2 x]] 1]) =>
