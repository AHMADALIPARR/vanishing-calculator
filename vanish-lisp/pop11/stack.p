;;; VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU Affero General Public License as published
;;; by the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; See the LICENSE file for the full text.

;;; stack.p --- Open value stack operations for VANISH-LISP POP-11 engine
;;; SPDX-License-Identifier: AGPL-3.0-or-later

vars vl_stack;
[] -> vl_stack;

define vl_stack_reset();
    [] -> vl_stack;
enddefine;

define vl_push(item);
    [^item ^^vl_stack] -> vl_stack;
enddefine;

define vl_pop() -> item;
    if null(vl_stack) then
        mishap(0, 'vl_pop: empty stack');
    endif;
    hd(vl_stack) -> item;
    tl(vl_stack) -> vl_stack;
enddefine;

define vl_peek() -> item;
    if null(vl_stack) then
        false -> item;
    else
        hd(vl_stack) -> item;
    endif;
enddefine;

define vl_dup();
    vars top;
    vl_peek() -> top;
    vl_push(top);
enddefine;

define vl_swap();
    vars a, b;
    vl_pop() -> a;
    vl_pop() -> b;
    vl_push(a);
    vl_push(b);
enddefine;

define vl_stack_depth() -> n;
    length(vl_stack) -> n;
enddefine;

;;; Evaluate a postfix (RPN) list of ring operations on the open stack
define vl_eval_rpn(tokens) -> result;
    vars tok, a, b;
    vl_stack_reset();
    for tok in tokens do
        if tok = "add" then
            vl_pop() -> b;
            vl_pop() -> a;
            vl_push([add ^a ^b]);
        elseif tok = "sub" then
            vl_pop() -> b;
            vl_pop() -> a;
            vl_push([sub ^a ^b]);
        elseif tok = "mul" then
            vl_pop() -> b;
            vl_pop() -> a;
            vl_push([mul ^a ^b]);
        else
            vl_push(tok);
        endif;
    endfor;
    vl_pop() -> result;
enddefine;
