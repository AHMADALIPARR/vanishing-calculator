;;; VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU Affero General Public License as published
;;; by the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; See the LICENSE file for the full text.

;;; vanish.p --- Top-level POP-11 symbolic reduction engine for VANISH-LISP
;;; SPDX-License-Identifier: AGPL-3.0-or-later

load('stack.p');
load('rewrite.p');
load('normalize.p');
load('polynomial.p');
load('groebner.p');

define vanish_reduce(expr) -> result;
    vl_rewrite_fixpoint(expr) -> result;
enddefine;

define vanish_eval(form) -> result;
    vars cs, body, gens, f, g_polys, f_poly;
    if form matches [under ?cs ?body] then
        vl_rewrite_fixpoint(body) -> result;
    elseif form matches [ideal [generators ??gens] ?f] then
        [% for g in gens do vl_to_poly(g) endfor %] -> g_polys;
        vl_to_poly(f) -> f_poly;
        vl_vanishing_certificate(g_polys, f_poly) -> result;
    else
        vl_rewrite_fixpoint(form) -> result;
    endif;
enddefine;

;;; Example smoke invocations
vanish_reduce([sub x x]) =>
vanish_reduce([mul 0 x]) =>
vanish_reduce([add x 0]) =>
