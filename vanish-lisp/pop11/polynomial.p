;;; polynomial.p --- Multivariate polynomial division and reduction
;;; SPDX-License-Identifier: MIT

define vl_mono_divides(m_div, m_num) -> flag;
    vars pair, v, e, found, p;
    true -> flag;
    for pair in m_div do
        pair(1) -> v;
        pair(2) -> e;
        false -> found;
        for p in m_num do
            if p(1) = v and p(2) >= e then
                true -> found;
            endif;
        endfor;
        if not(found) then
            false -> flag;
            return;
        endif;
    endfor;
enddefine;

define vl_mono_div(m_num, m_div) -> res;
    vars p, q, v, e, sub_e;
    [] -> res;
    for p in m_num do
        p(1) -> v;
        p(2) -> e;
        0 -> sub_e;
        for q in m_div do
            if q(1) = v then
                q(2) -> sub_e;
            endif;
        endfor;
        if e - sub_e > 0 then
            [^res [^v ^(e - sub_e)]] -> res;
        endif;
    endfor;
enddefine;

define vl_poly_lt(p) -> term;
    if null(p) then
        false -> term;
    else
        hd(p) -> term;
    endif;
enddefine;

;;; Multivariate division: f = sum(q_i * g_i) + r
;;; Returns [quotients remainder]
define vl_poly_divmod(f, gens) -> res;
    vars p, r, qs, i, n, divided, lt_p, g, lt_g, c_q, m_q, term_q, prod;
    f -> p;
    [] -> r;
    length(gens) -> n;
    [% for i from 1 to n do [] endfor %] -> qs;
    while not(null(p)) do
        false -> divided;
        vl_poly_lt(p) -> lt_p;
        for i from 1 to n do
            gens(i) -> g;
            if not(null(g)) and not(divided) then
                vl_poly_lt(g) -> lt_g;
                if vl_mono_divides(lt_g(2), lt_p(2)) and (lt_p(1) mod lt_g(1) = 0) then
                    lt_p(1) div lt_g(1) -> c_q;
                    vl_mono_div(lt_p(2), lt_g(2)) -> m_q;
                    [[^c_q ^m_q]] -> term_q;
                    vl_poly_add(qs(i), term_q) -> qs(i);
                    vl_poly_mul(term_q, g) -> prod;
                    vl_poly_sub(p, prod) -> p;
                    true -> divided;
                endif;
            endif;
        endfor;
        if not(divided) then
            vl_poly_add(r, [lt_p]) -> r;
            tl(p) -> p;
        endif;
    endwhile;
    [^qs ^r] -> res;
enddefine;
