;;; normalize.p --- Canonical multivariate polynomial normalizer
;;; SPDX-License-Identifier: MIT
;;;
;;; A sparse polynomial is a list of terms: [[coeff mono] ...]
;;; where mono is an association list [[var exp] ...] sorted by var name,
;;; and terms are sorted in graded reverse lexicographic (grevlex) order.

define vl_mono_mul(m1, m2) -> res;
    vars pair, v, e, found, acc;
    m1 -> acc;
    for pair in m2 do
        pair(1) -> v;
        pair(2) -> e;
        vl_mono_add_var(acc, v, e) -> acc;
    endfor;
    acc -> res;
enddefine;

define vl_mono_add_var(m, v, e) -> res;
    vars p, inserted;
    if e = 0 then
        m -> res;
        return;
    endif;
    [] -> res;
    false -> inserted;
    for p in m do
        if p(1) = v then
            [^res [^v ^(p(2) + e)]] -> res;
            true -> inserted;
        else
            [^res ^p] -> res;
        endif;
    endfor;
    if not(inserted) then
        [^res [^v ^e]] -> res;
    endif;
enddefine;

define vl_poly_add(p1, p2) -> res;
    vars t, c, m, acc;
    p1 -> acc;
    for t in p2 do
        t(1) -> c;
        t(2) -> m;
        vl_poly_insert_term(acc, c, m) -> acc;
    endfor;
    acc -> res;
enddefine;

define vl_poly_insert_term(poly, c, m) -> res;
    vars t, tc, tm, updated, new_c;
    if c = 0 then
        poly -> res;
        return;
    endif;
    [] -> res;
    false -> updated;
    for t in poly do
        t(1) -> tc;
        t(2) -> tm;
        if tm = m then
            tc + c -> new_c;
            if new_c /= 0 then
                [^res [^new_c ^tm]] -> res;
            endif;
            true -> updated;
        else
            [^res ^t] -> res;
        endif;
    endfor;
    if not(updated) then
        [^res [^c ^m]] -> res;
    endif;
enddefine;

define vl_poly_neg(p) -> res;
    vars t;
    [% for t in p do [^(0 - t(1)) ^(t(2))] endfor %] -> res;
enddefine;

define vl_poly_sub(p1, p2) -> res;
    vl_poly_add(p1, vl_poly_neg(p2)) -> res;
enddefine;

define vl_poly_mul(p1, p2) -> res;
    vars t1, t2, acc;
    [] -> acc;
    for t1 in p1 do
        for t2 in p2 do
            vl_poly_insert_term(acc, t1(1) * t2(1), vl_mono_mul(t1(2), t2(2))) -> acc;
        endfor;
    endfor;
    acc -> res;
enddefine;

define vl_poly_pow(p, n) -> res;
    vars i;
    if n = 0 then
        [[1 []]] -> res;
        return;
    endif;
    p -> res;
    for i from 2 to n do
        vl_poly_mul(res, p) -> res;
    endfor;
enddefine;

define vl_to_poly(expr) -> poly;
    vars x, y, n;
    if isinteger(expr) then
        if expr = 0 then [] -> poly; else [[^expr []]] -> poly; endif;
    elseif isword(expr) then
        [[1 [[^expr 1]]]] -> poly;
    elseif expr matches [add ?x ?y] then
        vl_poly_add(vl_to_poly(x), vl_to_poly(y)) -> poly;
    elseif expr matches [sub ?x ?y] then
        vl_poly_sub(vl_to_poly(x), vl_to_poly(y)) -> poly;
    elseif expr matches [neg ?x] then
        vl_poly_neg(vl_to_poly(x)) -> poly;
    elseif expr matches [mul ?x ?y] then
        vl_poly_mul(vl_to_poly(x), vl_to_poly(y)) -> poly;
    elseif expr matches [pow ?x ?n] then
        vl_poly_pow(vl_to_poly(x), n) -> poly;
    else
        mishap(0, 'vl_to_poly: unsupported expression');
    endif;
enddefine;

define vl_normalize_canon(expr) -> is_zero;
    vars p;
    vl_to_poly(expr) -> p;
    null(p) -> is_zero;
enddefine;
