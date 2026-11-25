/*
VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

See the LICENSE file for the full text.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>

#define ARENA_CAP 65536
#define SYM_CAP   4096

typedef enum {
    T_NIL = 0, T_INT, T_SYM, T_CONS, T_BUILTIN, T_LAMBDA, T_MACRO
} Tag;

typedef struct Cell Cell;
typedef int32_t Val; // Index into arena (0 = nil)
typedef Val (*BuiltinFn)(Val args, Val env);

struct Cell {
    Tag tag;
    union {
        int64_t ival;
        char *sym;
        struct { Val car, cdr; } pair;
        BuiltinFn fn;
        struct { Val params, body, env; } closure;
    };
};

static Cell arena[ARENA_CAP];
static int32_t arena_ptr = 1; // 0 is reserved for T_NIL
static char *sym_table[SYM_CAP];
static int32_t sym_count = 0;

static Val alloc_cell(Tag t) {
    if (arena_ptr >= ARENA_CAP) { fprintf(stderr, "Arena OOM\n"); exit(1); }
    Val idx = arena_ptr++;
    memset(&arena[idx], 0, sizeof(Cell));
    arena[idx].tag = t;
    return idx;
}

static Val mk_int(int64_t v) { Val c = alloc_cell(T_INT); arena[c].ival = v; return c; }
static Val cons(Val a, Val d) { Val c = alloc_cell(T_CONS); arena[c].pair.car = a; arena[c].pair.cdr = d; return c; }
static Val car(Val c) { return arena[c].tag == T_CONS ? arena[c].pair.car : 0; }
static Val cdr(Val c) { return arena[c].tag == T_CONS ? arena[c].pair.cdr : 0; }

static Val intern(const char *s) {
    for (int32_t i = 0; i < sym_count; i++) {
        if (strcmp(sym_table[i], s) == 0) {
            Val c = alloc_cell(T_SYM);
            arena[c].sym = sym_table[i];
            return c;
        }
    }
    char *dup = strdup(s);
    sym_table[sym_count++] = dup;
    Val c = alloc_cell(T_SYM);
    arena[c].sym = dup;
    return c;
}

static int sym_eq(Val c, const char *s) {
    return arena[c].tag == T_SYM && strcmp(arena[c].sym, s) == 0;
}

/* --- Reader --- */
static const char *src;
static void skip_ws(void) {
    while (*src) {
        if (isspace((unsigned char)*src)) { src++; continue; }
        if (*src == ';') { while (*src && *src != '\n') src++; continue; }
        break;
    }
}

static Val read_expr(void);
static Val read_list(void) {
    skip_ws();
    if (*src == ')') { src++; return 0; }
    Val head = read_expr();
    Val tail = read_list();
    return cons(head, tail);
}

static Val read_expr(void) {
    skip_ws();
    if (!*src) return 0;
    if (*src == '(') { src++; return read_list(); }
    if (*src == '\'') { src++; return cons(intern("quote"), cons(read_expr(), 0)); }
    char buf[128]; int n = 0;
    while (*src && !isspace((unsigned char)*src) && *src != '(' && *src != ')' && n < 127)
        buf[n++] = *src++;
    buf[n] = '\0';
    char *end; int64_t num = strtoll(buf, &end, 10);
    if (*buf && *end == '\0') return mk_int(num);
    return intern(buf);
}

/* --- Environment & Evaluator --- */
static Val env_bind(Val env, Val sym, Val val) { return cons(cons(sym, val), env); }
static Val env_lookup(Val env, Val sym) {
    for (Val e = env; e; e = cdr(e)) {
        Val b = car(e);
        if (strcmp(arena[car(b)].sym, arena[sym].sym) == 0) return cdr(b);
    }
    return 0;
}
static void env_set(Val env, Val sym, Val val) {
    for (Val e = env; e; e = cdr(e)) {
        Val b = car(e);
        if (strcmp(arena[car(b)].sym, arena[sym].sym) == 0) { arena[b].pair.cdr = val; return; }
    }
}

static Val eval(Val x, Val env);
static Val eval_list(Val list, Val env) {
    if (!list) return 0;
    return cons(eval(car(list), env), eval_list(cdr(list), env));
}

static Val eval_begin(Val seq, Val env) {
    Val res = 0;
    for (; seq; seq = cdr(seq)) res = eval(car(seq), env);
    return res;
}

static Val eval(Val x, Val env) {
    if (!x) return 0;
    if (arena[x].tag == T_INT) return x;
    if (arena[x].tag == T_SYM) return env_lookup(env, x);
    if (arena[x].tag != T_CONS) return x;

    Val op = car(x), args = cdr(x);
    if (sym_eq(op, "quote")) return car(args);
    if (sym_eq(op, "if")) {
        Val cond = eval(car(args), env);
        return (cond && !(arena[cond].tag == T_INT && arena[cond].ival == 0))
            ? eval(car(cdr(args)), env)
            : eval(car(cdr(cdr(args))), env);
    }
    if (sym_eq(op, "define")) {
        Val name = car(args), val = eval(car(cdr(args)), env);
        // Mutate top-level tail binding in place
        Val tail = env;
        while (cdr(tail)) tail = cdr(tail);
        arena[tail].pair.cdr = cons(cons(name, val), 0);
        return val;
    }
    if (sym_eq(op, "set!")) {
        Val val = eval(car(cdr(args)), env);
        env_set(env, car(args), val);
        return val;
    }
    if (sym_eq(op, "begin")) return eval_begin(args, env);
    if (sym_eq(op, "lambda") || sym_eq(op, "macro")) {
        Val fn = alloc_cell(sym_eq(op, "macro") ? T_MACRO : T_LAMBDA);
        arena[fn].closure.params = car(args);
        arena[fn].closure.body   = cdr(args);
        arena[fn].closure.env    = env;
        return fn;
    }
    /* Self-Modifying Primitives: mutate live AST cells or erase closure body */
    if (sym_eq(op, "set-car!")) {
        Val target = eval(car(args), env), new_car = eval(car(cdr(args)), env);
        if (arena[target].tag == T_CONS) arena[target].pair.car = new_car;
        return target;
    }
    if (sym_eq(op, "vanish!")) {
        Val fn = eval(car(args), env);
        if (arena[fn].tag == T_LAMBDA || arena[fn].tag == T_MACRO) {
            Val b = arena[fn].closure.body;
            memset(&arena[b], 0, sizeof(Cell)); // Zeroes the AST root in-place
            arena[fn].closure.body = 0;
        }
        return 0;
    }

    Val fn = eval(op, env);
    if (arena[fn].tag == T_BUILTIN) return arena[fn].fn(eval_list(args, env), env);
    if (arena[fn].tag == T_MACRO) {
        // Bind raw unevaluated AST forms, expand, then eval result
        Val call_env = arena[fn].closure.env;
        for (Val p = arena[fn].closure.params, a = args; p && a; p = cdr(p), a = cdr(a))
            call_env = env_bind(call_env, car(p), car(a));
        Val expanded = eval_begin(arena[fn].closure.body, call_env);
        return eval(expanded, env);
    }
    if (arena[fn].tag == T_LAMBDA) {
        Val ev_args = eval_list(args, env);
        Val call_env = arena[fn].closure.env;
        for (Val p = arena[fn].closure.params, a = ev_args; p && a; p = cdr(p), a = cdr(a))
            call_env = env_bind(call_env, car(p), car(a));
        return eval_begin(arena[fn].closure.body, call_env);
    }
    return 0;
}

/* --- Numeric & List Builtins --- */
static Val bi_add(Val a, Val e) { (void)e; return mk_int(arena[car(a)].ival + arena[car(cdr(a))].ival); }
static Val bi_sub(Val a, Val e) { (void)e; return mk_int(arena[car(a)].ival - arena[car(cdr(a))].ival); }
static Val bi_le (Val a, Val e) { (void)e; return mk_int(arena[car(a)].ival <= arena[car(cdr(a))].ival); }
static Val bi_eq (Val a, Val e) { (void)e; return mk_int(arena[car(a)].ival == arena[car(cdr(a))].ival); }
static Val bi_cons(Val a, Val e){ (void)e; return cons(car(a), car(cdr(a))); }
static Val bi_print(Val a, Val e){
    (void)e;
    for (Val x = car(a); x; x = cdr(x)) printf("%lld ", (long long)arena[car(x)].ival);
    printf("\n"); return 0;
}

static void reg_bi(Val *env, const char *name, BuiltinFn fn) {
    Val c = alloc_cell(T_BUILTIN); arena[c].fn = fn;
    *env = env_bind(*env, intern(name), c);
}

int main(void) {
    Val env = env_bind(0, intern("nil"), 0);
    reg_bi(&env, "+", bi_add); reg_bi(&env, "-", bi_sub);
    reg_bi(&env, "<=", bi_le); reg_bi(&env, "=", bi_eq);
    reg_bi(&env, "cons", bi_cons); reg_bi(&env, "print-list", bi_print);

    // Self-modifying Vanishing Fibonacci in Macro Lisp:
    // Computes fib(10), prints it, then calls (vanish! get-fib) to wipe its own AST cells.
    const char *prog =
        "(define defun (macro (name params body) (list 'define name (list 'lambda params body))))"
        "(define fib-loop (lambda (n a b acc)"
        "  (if (<= n 0) acc (fib-loop (- n 1) b (+ a b) (cons a acc)))))"
        "(define get-fib (lambda (n)"
        "  (begin"
        "    (define out (fib-loop n 0 1 nil))"
        "    (vanish! get-fib)"
        "    out)))"
        "(print-list (get-fib 10))"
        "(print-list (get-fib 10))"; // Second call returns nil: AST vanished after first run

    src = prog;
    while (*src) {
        skip_ws();
        if (!*src) break;
        eval(read_expr(), env);
    }
    return 0;
}
