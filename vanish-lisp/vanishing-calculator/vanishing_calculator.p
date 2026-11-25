/*
    Self-Modifying Vanishing Calculator (Poplog / Pop-11)
    STATE: VISIBLE
    Run under Poplog: pop11 vanishing_calculator.p
    or within a Poplog session: compile("vanishing_calculator.p");
    STAGED, NOT RUN on this VM: no pop11 runtime here (see STATUS.md).
    Arithmetic was verified only via a Python mirror of these functions.
*/

;;; STATE: VISIBLE

;;; Determine the script path (Poplog style)
vars script_path;
if popfilename then
    popfilename -> script_path;
else
    'vanishing_calculator.p' -> script_path;
endif;

;;; ============ CALCULATION ENGINE START ============
define calc_fibonacci(n) -> result;
    lvars a = 0, b = 1, i, c, result;
    if n <= 0 then
        '[]' -> result;
        return;
    elseif n == 1 then
        '[0]' -> result;
        return;
    endif;
    '[0, 1' -> result;
    for i from 2 to n-1 do
        a + b -> c;
        result <> ', ' <> c >< '' -> result;
        b -> a;
        c -> b;
    endfor;
    result <> ']' -> result;
enddefine;

;;; CLEANED (Muse 2026-11-23): the pasted calc_primes mixed three sieve
;;; attempts, used applist/maplist joins that do not produce "[2, 3, ...]",
;;; and left a trailing-comma hack. Replaced with one list-of-flags sieve
;;; in the same style, same name and return format. Original kept in STATUS.md.
define calc_primes(limit) -> result;
    lvars flags, i, j, result;
    if limit < 2 then
        '[]' -> result;
        return;
    endif;
    ;;; flags(k+1) is true while k is still a prime candidate
    initv(limit+1, true) -> flags;
    false -> flags(1);
    false -> flags(2);
    for i from 2 to intof(sqrt(limit)) do
        if flags(i+1) then
            for j from i*i by i to limit do
                false -> flags(j+1);
            endfor;
        endif;
    endfor;
    '[' -> result;
    for i from 2 to limit do
        if flags(i+1) then
            if result == '[' then
                result <> i >< '' -> result;
            else
                result <> ', ' <> i >< '' -> result;
            endif;
        endif;
    endfor;
    result <> ']' -> result;
enddefine;

define calc_factorial(n) -> result;
    lvars i, result = 1;
    if n < 0 then
        'null' -> result;
        return;
    endif;
    for i from 2 to n do
        result * i -> result;
    endfor;
enddefine;
;;; ============ CALCULATION ENGINE END ============

;;; Simple pure base64 (subset) for Poplog - using character codes
;;; FIXED (Muse 2026-11-23): precedence in the pasted index expressions.
;;; alphabet((n >> 18) && 63 + 1) parses as (n>>18) && (63+1); corrected
;;; to alphabet(((n >> 18) && 63) + 1), and likewise for the other nibbles.
define base64_encode(str) -> encoded;
    lvars alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',
          bytes = maplist(str, datakey),
          len = length(bytes),
          out = '', i, b0, b1, b2, n;
    for i from 1 by 3 to len do
        bytes(i) -> b0;
        if i+1 <= len then bytes(i+1) else 0 endif -> b1;
        if i+2 <= len then bytes(i+2) else 0 endif -> b2;
        (b0 << 16) || (b1 << 8) || b2 -> n;
        out <> alphabet(((n >> 18) && 63) + 1) -> out;
        out <> alphabet(((n >> 12) && 63) + 1) -> out;
        if i+1 <= len then
            out <> alphabet(((n >> 6) && 63) + 1) -> out;
        else
            out <> '=' -> out;
        endif;
        if i+2 <= len then
            out <> alphabet((n && 63) + 1) -> out;
        else
            out <> '=' -> out;
        endif;
    endfor;
    out -> encoded;
enddefine;

;;; RECONSTRUCTED (Muse 2026-11-23): no base64 decoder was in the paste.
define b64_val(c) -> v;
    lvars alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',
          k, v = 0, c;
    for k from 1 to 64 do
        if alphabet(k) == c then
            k - 1 -> v;
            return;
        endif;
    endfor;
enddefine;

define base64_decode(str) -> decoded;
    lvars alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',
          clean = '', i, c0, c1, c2, c3, n, decoded = '', k, c;
    for k from 1 to datalength(str) do
        str(k) -> c;
        if c /= `=` then
            clean <> c -> clean;
        endif;
    endfor;
    for i from 1 by 4 to datalength(clean) do
        b64_val(clean(i)) -> c0;
        b64_val(clean(i+1)) -> c1;
        if i+2 <= datalength(clean) then b64_val(clean(i+2)) else 0 endif -> c2;
        if i+3 <= datalength(clean) then b64_val(clean(i+3)) else 0 endif -> c3;
        (c0 << 18) || (c1 << 12) || (c2 << 6) || c3 -> n;
        decoded <> consstring((n >> 16) && 255, 1) -> decoded;
        if i+2 <= datalength(clean) then
            decoded <> consstring((n >> 8) && 255, 1) -> decoded;
        endif;
        if i+3 <= datalength(clean) then
            decoded <> consstring(n && 255, 1) -> decoded;
        endif;
    endfor;
    decoded -> decoded;
enddefine;

;;; RECONSTRUCTED (Muse 2026-11-23): make_hidden / make_visible / main were
;;; cut off in the paste; completed from the PowerShell/Racket pattern in
;;; the same paste, using issubstring for the marker search.
define read_file_string(path) -> content;
    lvars dev, content = '', c;
    discin(path) -> dev;
    until (discin_char(dev) ->> c) == termin do
        content <> consstring(c, 1) -> content;
    enduntil;
    sysclose(dev);
enddefine;

define write_file_string(path, content);
    lvars dev;
    discout(path) -> dev;
    dev(content);
    sysclose(dev);
enddefine;

define replace_once(str, old, new) -> out;
    lvars str, old, new, out, pos;
    issubstring(old, 1, str) -> pos;
    if pos then
        substring(1, pos - 1, str) <> new <> substring(pos + datalength(old), datalength(str), str) -> out;
    else
        str -> out;
    endif;
enddefine;

define make_hidden();
    lvars content, start_marker, end_marker, start_idx, end_idx,
          before, hidden, after, encoded, new_content;
    read_file_string(script_path) -> content;
    ';;; ============ CALCULATION ENGINE START ============' -> start_marker;
    ';;; ============ CALCULATION ENGINE END ============' -> end_marker;
    issubstring(start_marker, 1, content) -> start_idx;
    issubstring(end_marker, 1, content) -> end_idx;
    if start_idx == false or end_idx == false then
        'Could not find markers' ->> mishap('vanishing_calculator', []);
        return;
    endif;
    substring(1, start_idx + datalength(start_marker) - 1, content) -> before;
    substring(start_idx + datalength(start_marker), end_idx - 1, content) -> hidden;
    substring(end_idx, datalength(content), content) -> after;
    base64_encode(hidden) -> encoded;
    before <> '\n;;; [ENGINE HIDDEN - Run again to restore]\n' <>
        'vars hidden_payload;\n\'' <> encoded <> '\' -> hidden_payload;\n' <> after -> new_content;
    replace_once(new_content, ';;; STATE: VISIBLE', ';;; STATE: HIDDEN') -> new_content;
    write_file_string(script_path, new_content);
    '\n[✓] Rewrote: ' <> script_path => ;
enddefine;

define make_visible();
    lvars content, payload_start, enc_start, enc_end, encoded, decoded,
          start_marker, end_marker, start_idx, end_idx,
          before, after, new_content;
    read_file_string(script_path) -> content;
    issubstring('hidden_payload;', 1, content) -> payload_start;
    if payload_start == false then
        'No hidden payload found' ->> mishap('vanishing_calculator', []);
        return;
    endif;
    ;;; payload is: '...' -> hidden_payload;  find the quoted string
    issubstring('\'', payload_start, content) -> enc_start;
    issubstring('\'', enc_start + 1, content) -> enc_end;
    substring(enc_start + 1, enc_end - 1, content) -> encoded;
    base64_decode(encoded) -> decoded;
    ';;; ============ CALCULATION ENGINE START ============' -> start_marker;
    ';;; ============ CALCULATION ENGINE END ============' -> end_marker;
    issubstring(start_marker, 1, content) -> start_idx;
    issubstring(end_marker, 1, content) -> end_idx;
    if start_idx == false or end_idx == false then
        'Could not find markers' ->> mishap('vanishing_calculator', []);
        return;
    endif;
    substring(1, start_idx + datalength(start_marker) - 1, content) -> before;
    substring(end_idx, datalength(content), content) -> after;
    before <> decoded <> after -> new_content;
    replace_once(new_content, ';;; STATE: HIDDEN', ';;; STATE: VISIBLE') -> new_content;
    write_file_string(script_path, new_content);
    '\n[✓] Rewrote: ' <> script_path => ;
enddefine;

;;; Main toggle: visible -> calculate, then hide; hidden -> restore, then stop.
lvars main_content;
read_file_string(script_path) -> main_content;
'=======================================================' => ;
' SELF-MODIFYING VANISHING CALCULATOR (POPLOG)' => ;
'=======================================================' => ;
;;; FIXED (Muse 2026-11-23): a whole-file issubstring always hits, because
;;; the toggle code itself contains ';;; STATE: VISIBLE'. Require the
;;; newline before it, so only the header line matches.
if issubstring('\n;;; STATE: VISIBLE', 1, main_content) then
    '\nSTATE: VISIBLE - Calculation Engine is ACTIVE\n' => ;
    'Fibonacci(10): ' <> calc_fibonacci(10) => ;
    'Primes(30): ' <> calc_primes(30) => ;
    'Factorial(5): ' <> calc_factorial(5) => ;
    make_hidden();
else
    '\nSTATE: HIDDEN - Calculation Engine is HIDDEN\n' => ;
    make_visible();
    'Engine restored. Run again to calculate.' => ;
endif;
