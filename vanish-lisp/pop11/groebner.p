;;; VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU Affero General Public License as published
;;; by the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; See the LICENSE file for the full text.

;;; groebner.p --- S-polynomials, Buchberger reduction, and vanishing certificates
;;; SPDX-License-Identifier: AGPL-3.0-or-later

define vl_mono_lcm(m1, m2) -> res;
    vars p, v, e;
    m1 -> res;
    for p in m2 do
        p(1) -> v;
        p(2) -> e;
        vl_mono_max_var(res, v, e) -> res;
    endfor;
enddefine;

define vl_mono_max_var(m, v, e) -> res;
    vars p, found;
    [] -> res;
    false -> found;
    for p in m do
        if p(1) = v then
            [^res [^v ^(max(p(2), e))]] -> res;
            true -> found;
        else
            [^res ^p] -> res;
        endif;
    endfor;
    if not(found) then
        [^res [^v ^e]] -> res;
    endif;
enddefine;

define vl_spoly(f, g) -> s;
    vars ltf, ltg, lcm_m, mf, mg, tf, tg;
    vl_poly_lt(f) -> ltf;
    vl_poly_lt(g) -> ltg;
    vl_mono_lcm(ltf(2), ltg(2)) -> lcm_m;
    vl_mono_div(lcm_m, ltf(2)) -> mf;
    vl_mono_div(lcm_m, ltg(2)) -> mg;
    [[^(ltg(1)) ^mf]] -> tf;
    [[^(ltf(1)) ^mg]] -> tg;
    vl_poly_sub(vl_poly_mul(tf, f), vl_poly_mul(tg, g)) -> s;
enddefine;

define vl_buchberger(gens) -> basis;
    vars pairs, i, j, n, p, s, divres, rem;
    gens -> basis;
    [] -> pairs;
    length(basis) -> n;
    for i from 1 to n do
        for j from i + 1 to n do
            [^pairs [^i ^j]] -> pairs;
        endfor;
    endfor;
    while not(null(pairs)) do
        hd(pairs) -> p;
        tl(pairs) -> pairs;
        vl_spoly(basis(p(1)), basis(p(2))) -> s;
        vl_poly_divmod(s, basis) -> divres;
        divres(2) -> rem;
        if not(null(rem)) then
            [^basis ^rem] -> basis;
            length(basis) -> n;
            for i from 1 to n - 1 do
                [^pairs [^i ^n]] -> pairs;
            endfor;
        endif;
    endwhile;
enddefine;

;;; Produce a vanishing certificate [cert quotients remainder verdict]
define vl_vanishing_certificate(gens, f) -> cert;
    vars basis, divres, qs, rem, verdict;
    vl_buchberger(gens) -> basis;
    vl_poly_divmod(f, basis) -> divres;
    divres(1) -> qs;
    divres(2) -> rem;
    if null(rem) then
        1 -> verdict;
    else
        "bot" -> verdict;
    endif;
    [cert ^qs ^rem ^verdict] -> cert;
enddefine;
