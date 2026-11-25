;;; VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU Affero General Public License as published
;;; by the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; See the LICENSE file for the full text.

;;; ideal-cases.p --- POP-11 ideal membership test cases
;;; SPDX-License-Identifier: AGPL-3.0-or-later

load('../../pop11/vanish.p');

;;; Test: x^4 - 1 in <x^2 - 1>
vanish_eval([ideal [generators [sub [pow x 2] 1]] [sub [pow x 4] 1]]) =>

;;; Test: (x + 1)^2 - x^2 - 2x - 1 vanishes identically
vl_normalize_canon([sub [sub [sub [pow [add x 1] 2] [pow x 2]] [mul 2 x]] 1]) =>
