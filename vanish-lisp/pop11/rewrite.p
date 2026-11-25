;;; VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU Affero General Public License as published
;;; by the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; See the LICENSE file for the full text.

;;; rewrite.p --- Pattern-matching term rewrite rules for VANISH-LISP
;;; SPDX-License-Identifier: AGPL-3.0-or-later

define vl_rewrite_step(expr) -> result;
    vars x, y, v, n, a, b;
    if isinteger(expr) or isword(expr) then
        expr -> result;
    elseif expr matches [sub ?x ?y] then
        vl_rewrite_step(x) -> a;
        vl_rewrite_step(y) -> b;
        if a = b then
            0 -> result;
        elseif isinteger(a) and isinteger(b) then
            a - b -> result;
        elseif b = 0 then
            a -> result;
        else
            [sub ^a ^b] -> result;
        endif;
    elseif expr matches [neg ?x] then
        vl_rewrite_step(x) -> a;
        if a = 0 then
            0 -> result;
        elseif isinteger(a) then
            0 - a -> result;
        else
            [neg ^a] -> result;
        endif;
    elseif expr matches [mul ?x ?y] then
        vl_rewrite_step(x) -> a;
        vl_rewrite_step(y) -> b;
        if a = 0 or b = 0 then
            0 -> result;
        elseif a = 1 then
            b -> result;
        elseif b = 1 then
            a -> result;
        elseif isinteger(a) and isinteger(b) then
            a * b -> result;
        else
            [mul ^a ^b] -> result;
        endif;
    elseif expr matches [add ?x ?y] then
        vl_rewrite_step(x) -> a;
        vl_rewrite_step(y) -> b;
        if a = 0 then
            b -> result;
        elseif b = 0 then
            a -> result;
        elseif isinteger(a) and isinteger(b) then
            a + b -> result;
        else
            [add ^a ^b] -> result;
        endif;
    elseif expr matches [pow ?x ?n] then
        vl_rewrite_step(x) -> a;
        if n = 0 then
            1 -> result;
        elseif n = 1 then
            a -> result;
        elseif a = 0 then
            0 -> result;
        elseif a = 1 then
            1 -> result;
        else
            [pow ^a ^n] -> result;
        endif;
    elseif expr matches [deriv ?v ?x] then
        vl_deriv_step(v, x) -> result;
    else
        expr -> result;
    endif;
enddefine;

define vl_deriv_step(v, expr) -> result;
    vars x, y, n;
    if isinteger(expr) then
        0 -> result;
    elseif isword(expr) then
        if expr = v then 1 -> result; else 0 -> result; endif;
    elseif expr matches [add ?x ?y] then
        vl_rewrite_step([add ^(vl_deriv_step(v, x)) ^(vl_deriv_step(v, y))]) -> result;
    elseif expr matches [sub ?x ?y] then
        vl_rewrite_step([sub ^(vl_deriv_step(v, x)) ^(vl_deriv_step(v, y))]) -> result;
    elseif expr matches [mul ?x ?y] then
        vl_rewrite_step([add [mul ^(vl_deriv_step(v, x)) ^y]
                             [mul ^x ^(vl_deriv_step(v, y))]]) -> result;
    elseif expr matches [pow ?x ?n] then
        if n = 0 then
            0 -> result;
        else
            vl_rewrite_step([mul ^n [mul [pow ^x ^(n - 1)] ^(vl_deriv_step(v, x))]]) -> result;
        endif;
    else
        [deriv ^v ^expr] -> result;
    endif;
enddefine;

define vl_rewrite_fixpoint(expr) -> result;
    vars prev, cur;
    expr -> cur;
    repeat
        cur -> prev;
        vl_rewrite_step(prev) -> cur;
        quitif(cur = prev);
    endrepeat;
    cur -> result;
enddefine;
