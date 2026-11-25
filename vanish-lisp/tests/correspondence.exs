#!/usr/bin/env elixir
# VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# See the LICENSE file for the full text.

# tests/correspondence.exs -- Exhaustive correspondence corpus check.
#
# Runs the real XSLT lowering on the real Scheme-emitted XML for every
# well-formed expression of depth at most 2 over variables {x, y} and
# literals {0, 1} with exponents {0, 1, 2} (14,148 expressions), plus
# 30 hand-picked edge cases (negative literals, exponent 3 and 4,
# deeper nesting, n-ary surface forms), 14,164 expressions in total.
# For each one it checks five things:
#   determinism       the lowering run twice is byte-identical
#   decode            the Scheme XML decodes to the canonical form
#   lowering==compile the lowering equals the Lean compile
#   lowering==lowerXml the lowering equals the formalized lowerXml
#   trailing          no trailing instruction is missing
# The Lean side runs in chunks of 500 expressions per run: elaborating
# one giant List Expr literal is severely superlinear.
#
# The XSLT lowering itself is driven through `xsltproc` directly (the
# same engine tests/xslt.exs fronts); spawning an Elixir VM per
# expression would dominate the runtime. This is differential testing,
# not the proof: the universal theorem is Vanish.correspondence in
# lean/Vanish/Correspondence.lean.
#
# Usage:
#   elixir tests/correspondence.exs            # full corpus
#   elixir tests/correspondence.exs --one SEXPR  # one expression

defmodule Correspondence do
  @chunk_size 500
  @expected_total 14_164

  # Expr: {:lit, n} | {:var, name} | {:add, a, b} | {:sub, a, b} |
  #       {:neg, a} | {:mul, a, b} | {:pow, a, n}
  # XmlTree: {:int, n} | {:sym, name} | {:add, a, b} | {:sub, a, b} |
  #          {:mul, a, b} | {:pow, a, b}

  def main(["--one", sexpr]) do
    expr = parse_sexp(String.trim(sexpr))
    result = check_one(expr)
    print_checks(result)
    if Enum.all?(result, fn {_k, v} -> v end), do: System.halt(0), else: System.halt(1)
  end

  def main([]) do
    exprs = corpus()
    IO.puts("correspondence corpus: #{length(exprs)} expressions")
    results = check_all(exprs)
    failures = Enum.filter(results, fn {_expr, checks} -> not Enum.all?(checks, fn {_k, v} -> v end) end)

    counts =
      [:determinism, :decode, :compile, :lower_xml, :trailing]
      |> Map.new(fn key -> {key, Enum.count(results, fn {_e, c} -> c[key] end)} end)

    IO.puts("determinism: #{pass(counts.determinism, length(exprs))}")
    IO.puts("decode: #{pass(counts.decode, length(exprs))}")
    IO.puts("lowering==compile: #{pass(counts.compile, length(exprs))}")
    IO.puts("lowering==lowerXml: #{pass(counts.lower_xml, length(exprs))}")
    IO.puts("trailing: #{pass(counts.trailing, length(exprs))}")

    if failures == [] do
      IO.puts("correspondence corpus: PASS (#{length(exprs)} expressions)")
    else
      IO.puts(:stderr, "correspondence corpus: FAIL (#{length(failures)} failing expressions)")
      failures |> Enum.take(5) |> Enum.each(fn {expr, checks} ->
        IO.puts(:stderr, "  FAIL: #{render_sexp(expr)} #{inspect(checks)}")
      end)
      System.halt(1)
    end
  end

  def main(_), do: usage_error()

  defp usage_error do
    IO.puts(:stderr, "usage: elixir tests/correspondence.exs [--one SEXPR]")
    System.halt(2)
  end

  defp pass(n, total) when n == total, do: "PASS"
  defp pass(n, total), do: "FAIL (#{n}/#{total})"

  # ------------------------------------------------------------------
  # Corpus enumeration
  # ------------------------------------------------------------------

  defp corpus do
    atoms = [{:lit, 0}, {:lit, 1}, {:var, "x"}, {:var, "y"}]
    d1 = depth_one(atoms)
    e1 = atoms ++ d1
    d2 = depth_two(e1, d1)
    base = atoms ++ d1 ++ d2
    edges = edge_cases() |> Enum.map(&parse_sexp/1)
    all = Enum.uniq(base ++ edges)

    unless length(all) == @expected_total do
      raise "correspondence: corpus has #{length(all)} unique expressions, expected #{@expected_total}"
    end

    all
  end

  defp depth_one(atoms) do
    negs = Enum.map(atoms, &{:neg, &1})

    binaries =
      for a <- atoms, b <- atoms, op <- [:add, :sub, :mul] do
        {op, a, b}
      end

    pows = for a <- atoms, n <- 0..2, do: {:pow, a, n}
    negs ++ binaries ++ pows
  end

  defp depth_two(e1, d1) do
    negs = Enum.map(d1, &{:neg, &1})

    binaries =
      for a <- e1, b <- e1, op <- [:add, :sub, :mul],
          max(depth(a), depth(b)) == 1 do
        {op, a, b}
      end

    pows = for a <- d1, n <- 0..2, do: {:pow, a, n}
    negs ++ binaries ++ pows
  end

  defp depth({:lit, _}), do: 0
  defp depth({:var, _}), do: 0
  defp depth({:neg, a}), do: depth(a) + 1
  defp depth({:pow, a, _}), do: depth(a) + 1
  defp depth({_op, a, b}), do: max(depth(a), depth(b)) + 1

  # 30 edge cases: 16 new expressions, 14 already in the corpus.
  defp edge_cases do
    [
      "(- 5)", "(- 42)", "(- 100)",
      "(- 0)", "(- 1)", "(- x)", "(- y)",
      "(pow x 4)", "(pow y 4)", "(pow (+ x y) 4)",
      "(pow x 0)", "(pow (* x y) 2)",
      "(+ (+ (+ x y) 1) x)",
      "(+ (+ (+ x y) (+ x y)) 1)",
      "(* (pow x 2) (pow x 3))",
      "(+ x y 0)", "(* x y 1)",
      "(+ x y 1 0)", "(- x y 0)",
      "(pow (+ x 1) 3)",
      "(- (pow x 4) 1)",
      "(- 0 1)", "(vanish (- x x))",
      "(* (- x y) (+ x y))", "(- (* x x) (* y y))",
      "(+ (pow x 3) 1)", "(* x x x x)",
      "(pow y 3)", "(- (pow y 4) (pow x 4))",
      "(vanish (+ x 1))"
    ]
  end

  # ------------------------------------------------------------------
  # S-expression rendering and parsing
  # ------------------------------------------------------------------

  defp render_sexp({:lit, n}), do: Integer.to_string(n)
  defp render_sexp({:var, x}), do: x
  defp render_sexp({:add, a, b}), do: "(+ #{render_sexp(a)} #{render_sexp(b)})"
  defp render_sexp({:sub, a, b}), do: "(- #{render_sexp(a)} #{render_sexp(b)})"
  defp render_sexp({:neg, a}), do: "(- #{render_sexp(a)})"
  defp render_sexp({:mul, a, b}), do: "(* #{render_sexp(a)} #{render_sexp(b)})"
  defp render_sexp({:pow, a, n}), do: "(pow #{render_sexp(a)} #{n})"

  defp parse_sexp(str) do
    tokens = tokenize(str)
    {expr, []} = parse_tokens(tokens)
    expr
  end

  defp tokenize(str) do
    str
    |> String.replace("(", " ( ")
    |> String.replace(")", " ) ")
    |> String.split()
  end

  defp parse_tokens(["(" | rest]) do
    [op | rest1] = rest
    {args, rest2} = parse_args(rest1, [])
    {build(op, args), rest2}
  end

  defp parse_tokens([atom | rest]), do: {parse_atom(atom), rest}
  defp parse_tokens([]), do: raise("correspondence: unexpected end of S-expression")

  defp parse_args([")" | rest], acc), do: {Enum.reverse(acc), rest}

  defp parse_args(tokens, acc) do
    {expr, rest} = parse_tokens(tokens)
    parse_args(rest, [expr | acc])
  end

  defp parse_atom(atom) do
    case Integer.parse(atom) do
      {n, ""} -> {:lit, n}
      _ -> {:var, atom}
    end
  end

  defp build("vanish", [inner]), do: inner
  defp build("-", [a]), do: {:neg, a}
  defp build(op, args) when op in ["+", "add"] and length(args) >= 2,
    do: Enum.reduce(tl(args), hd(args), &{:add, &2, &1})
  defp build(op, args) when op in ["-", "sub"] and length(args) >= 2,
    do: Enum.reduce(tl(args), hd(args), &{:sub, &2, &1})
  defp build(op, args) when op in ["*", "mul"] and length(args) >= 2,
    do: Enum.reduce(tl(args), hd(args), &{:mul, &2, &1})
  defp build("pow", [a, {:lit, n}]) when n >= 0, do: {:pow, a, n}
  defp build(op, args), do: raise("correspondence: unsupported form (#{op} #{inspect(args)})")

  # ------------------------------------------------------------------
  # Canonical form (unary minus eliminated to subtraction from zero)
  # ------------------------------------------------------------------

  defp canon({:lit, n}), do: {:lit, n}
  defp canon({:var, x}), do: {:var, x}
  defp canon({:add, a, b}), do: {:add, canon(a), canon(b)}
  defp canon({:sub, a, b}), do: {:sub, canon(a), canon(b)}
  defp canon({:neg, a}), do: {:sub, {:lit, 0}, canon(a)}
  defp canon({:mul, a, b}), do: {:mul, canon(a), canon(b)}
  defp canon({:pow, a, n}), do: {:pow, canon(a), n}

  # ------------------------------------------------------------------
  # Checking
  # ------------------------------------------------------------------

  defp check_all(exprs) do
    root = root_dir()
    xmls = emit_xml(root, exprs)
    lowered = lower_all(root, xmls)
    lean = lean_all(root, exprs)

    Enum.zip([exprs, xmls, lowered, lean])
    |> Enum.map(fn {expr, xml, {lower1, lower2}, {compile_text, lower_xml_text}} ->
      {expr, checks_for(expr, xml, lower1, lower2, compile_text, lower_xml_text)}
    end)
  end

  defp check_one(expr) do
    root = root_dir()
    [xml] = emit_xml(root, [expr])
    [{lower1, lower2}] = lower_all(root, [xml])
    [{compile_text, lower_xml_text}] = lean_all(root, [expr])
    checks_for(expr, xml, lower1, lower2, compile_text, lower_xml_text)
  end

  defp checks_for(expr, xml, lower1, lower2, compile_text, lower_xml_text) do
    lower_text = program_text(lower1)
    decoded = xml |> parse_xml_tree() |> decode()

    %{
      determinism: lower1 == lower2,
      decode: decoded == {:ok, canon(expr)},
      compile: lower_text == compile_text,
      lower_xml: lower_text == lower_xml_text,
      trailing: trailing_ok?(lower_text)
    }
  end

  defp trailing_ok?(text) do
    lines = String.split(text, "\n", trim: true)
    Enum.take(lines, -4) == ["NORMALIZE", "ASSERT_ZERO", "VERIFY_PROOF", "HALT"]
  end

  defp print_checks(checks) do
    IO.puts("determinism: #{if checks.determinism, do: "PASS", else: "FAIL"}")
    IO.puts("decode: #{if checks.decode, do: "PASS", else: "FAIL"}")
    IO.puts("lowering==compile: #{if checks.compile, do: "PASS", else: "FAIL"}")
    IO.puts("lowering==lowerXml: #{if checks.lower_xml, do: "PASS", else: "FAIL"}")
    IO.puts("trailing: #{if checks.trailing, do: "PASS", else: "FAIL"}")
  end

  # One Racket process for the whole corpus: the real Scheme emitter
  # (scheme/vanish.rkt, sexp->xml) end to end. System.cmd cannot feed
  # a process stdin, so the expressions go through a temp file.
  defp emit_xml(root, exprs) do
    work = Path.join([root, "tests", ".pipeline-work"])
    File.mkdir_p!(work)
    input_file = Path.join(work, "corr-exprs.sexp")
    input = exprs |> Enum.map(&render_sexp/1) |> Enum.join("\n")
    File.write!(input_file, input <> "\n")
    racket = System.find_executable("racket") || raise "correspondence: racket not on PATH"
    batch = Path.join([root, "scheme", "batch-xml.rkt"])

    cmd = "#{shell_quote(racket)} #{shell_quote(batch)} < #{shell_quote(input_file)}"

    case System.cmd("sh", ["-c", cmd], cd: root, stderr_to_stdout: true) do
      {output, 0} ->
        lines = String.split(output, "\n", trim: true)

        if length(lines) == length(exprs) do
          lines
        else
          raise "correspondence: batch-xml emitted #{length(lines)} documents for #{length(exprs)} expressions"
        end

      {output, code} ->
        raise "correspondence: batch-xml failed (exit #{code}): #{output}"
    end
  end

  defp shell_quote(path), do: "'" <> String.replace(path, "'", "'\\''") <> "'"

  # Real XSLT lowering per expression: canonicalize, then lower twice
  # (determinism). Run in parallel across schedulers.
  defp lower_all(root, xmls) do
    xmls
    |> Task.async_stream(
      fn xml ->
        canon = xslt(root, "xslt/canonicalize.xsl", xml)
        {xslt(root, "xslt/lower.xsl", canon), xslt(root, "xslt/lower.xsl", canon)}
      end,
      max_concurrency: System.schedulers_online(),
      timeout: 120_000
    )
    |> Enum.map(fn {:ok, pair} -> pair end)
  end

  defp xslt(root, stylesheet, xml) do
    xsltproc = System.find_executable("xsltproc") || raise "correspondence: xsltproc not on PATH"
    work = Path.join([root, "tests", ".pipeline-work"])
    tmp = Path.join(work, "corr-#{:erlang.unique_integer([:positive])}.xml")

    try do
      File.write!(tmp, xml)

      case System.cmd(xsltproc, [Path.join(root, stylesheet), tmp], cd: root) do
        {output, 0} -> output
        {output, code} -> raise "correspondence: xsltproc #{stylesheet} failed (exit #{code}): #{output}"
      end
    after
      File.rm(tmp)
    end
  end

  # Batched Lean runs: compile and lowerXml for each expression, in
  # chunks of 500. Returns [{compile_text, lower_xml_text}] in order.
  defp lean_all(root, exprs) do
    work = Path.join([root, "tests", ".pipeline-work"])
    File.mkdir_p!(work)
    lake = System.find_executable("lake") || raise "correspondence: lake not on PATH"

    exprs
    |> Enum.chunk_every(@chunk_size)
    |> Enum.with_index()
    |> Enum.flat_map(fn {chunk, i} ->
      file = Path.join(work, "corr-batch-#{i}.lean")
      File.write!(file, lean_batch(chunk))

      case System.cmd(lake, ["env", "lean", file], cd: root, stderr_to_stdout: true) do
        {output, 0} -> parse_lean_batch(output, length(chunk))
        {output, code} -> raise "correspondence: lean batch #{i} failed (exit #{code}): #{output}"
      end
    end)
  end

  defp lean_batch(chunk) do
    header = """
    import Vanish.Pipeline
    import Vanish.Correspondence

    open Vanish

    def showOne (e : Expr) : IO Unit := do
      IO.println "---EXPR---"
      for i in compile e ++ [Instr.normalize, Instr.assertZero, Instr.verifyProof, Instr.halt] do
        IO.println (instrToText i)
      IO.println "---LOWERXML---"
      for i in lowerProgram (encode e) do
        IO.println (instrToText i)

    """

    evals =
      chunk
      |> Enum.map(fn expr -> "#eval showOne (#{lean_expr(expr)})" end)
      |> Enum.join("\n")

    header <> evals <> "\n"
  end

  defp lean_expr({:lit, n}) when n >= 0, do: "Expr.lit #{n}"
  defp lean_expr({:lit, n}), do: "Expr.lit (#{n})"
  defp lean_expr({:var, x}), do: "Expr.var \"#{x}\""
  defp lean_expr({:add, a, b}), do: "Expr.add (#{lean_expr(a)}) (#{lean_expr(b)})"
  defp lean_expr({:sub, a, b}), do: "Expr.sub (#{lean_expr(a)}) (#{lean_expr(b)})"
  defp lean_expr({:neg, a}), do: "Expr.neg (#{lean_expr(a)})"
  defp lean_expr({:mul, a, b}), do: "Expr.mul (#{lean_expr(a)}) (#{lean_expr(b)})"
  defp lean_expr({:pow, a, n}), do: "Expr.pow (#{lean_expr(a)}) #{n}"

  defp parse_lean_batch(output, count) do
    blocks =
      output
      |> String.split("---EXPR---", trim: true)
      |> Enum.map(fn block ->
        case String.split(block, "---LOWERXML---", parts: 2) do
          [compile_part, lower_part] -> {String.trim(compile_part), String.trim(lower_part)}
          _ -> raise "correspondence: malformed lean batch output"
        end
      end)

    if length(blocks) == count do
      blocks
    else
      raise "correspondence: lean batch returned #{length(blocks)} results for #{count} expressions"
    end
  end

  # ------------------------------------------------------------------
  # XML decoding (Elixir mirror of Vanish.decode)
  # ------------------------------------------------------------------

  defp parse_xml_tree(xml) do
    {doc, _} = :xmerl_scan.string(String.to_charlist(xml))
    xml_to_tree(doc)
  end

  defp xml_to_tree({:xmlElement, :vanish, _, _, _, _, _, _, content, _, _, _}) do
    [expr] = element_children(content)
    xml_to_tree(expr)
  end

  defp xml_to_tree({:xmlElement, :expr, _, _, _, _, _, _, content, _, _, _}) do
    [inner] = element_children(content)
    xml_to_tree(inner)
  end

  defp xml_to_tree({:xmlElement, :integer, _, _, _, _, _, _, content, _, _, _}),
    do: {:int, content |> text_of() |> String.trim() |> String.to_integer()}

  defp xml_to_tree({:xmlElement, :symbol, _, _, _, _, _, _, content, _, _, _}),
    do: {:sym, content |> text_of() |> String.trim()}

  defp xml_to_tree({:xmlElement, op, _, _, _, _, _, _, content, _, _, _})
       when op in [:add, :sub, :mul, :pow] do
    [a, b] = element_children(content)
    {op, xml_to_tree(a), xml_to_tree(b)}
  end

  defp text_of(content) do
    content
    |> Enum.filter(&match?({:xmlText, _, _, _, _, _}, &1))
    |> Enum.map(fn {:xmlText, _, _, _, value, _} -> List.to_string(value) end)
    |> Enum.join("")
  end

  defp element_children(content) do
    Enum.filter(content, &match?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, &1))
  end

  defp decode({:int, n}), do: {:ok, {:lit, n}}
  defp decode({:sym, x}), do: {:ok, {:var, x}}

  defp decode({:add, a, b}),
    do: with({:ok, a2} <- decode(a), {:ok, b2} <- decode(b), do: {:ok, {:add, a2, b2}})

  defp decode({:sub, a, b}),
    do: with({:ok, a2} <- decode(a), {:ok, b2} <- decode(b), do: {:ok, {:sub, a2, b2}})

  defp decode({:mul, a, b}),
    do: with({:ok, a2} <- decode(a), {:ok, b2} <- decode(b), do: {:ok, {:mul, a2, b2}})

  defp decode({:pow, a, {:int, n}}) when n >= 0,
    do: with({:ok, a2} <- decode(a), do: {:ok, {:pow, a2, n}})

  defp decode({:pow, _, _}), do: :error

  # program_to_text on the lowered program XML.
  defp program_text(prog_xml) do
    {doc, _} = :xmerl_scan.string(String.to_charlist(prog_xml))
    {:xmlElement, :program, _, _, _, _, _, _, content, _, _, _} = doc

    content
    |> Enum.filter(&match?({:xmlElement, :instruction, _, _, _, _, _, _, _, _, _, _}, &1))
    |> Enum.map(fn {:xmlElement, :instruction, _, _, _, _, _, attrs, content, _, _, _} ->
      opcode =
        attrs
        |> Enum.find(fn {:xmlAttribute, n, _, _, _, _, _, _, _, _} -> n == :opcode end)
        |> then(fn {:xmlAttribute, _, _, _, _, _, _, _, value, _} -> List.to_string(value) end)

      text = text_of(content)
      if text == "", do: opcode, else: opcode <> " " <> text
    end)
    |> Enum.join("\n")
  end

  defp root_dir, do: Path.expand("..", __DIR__)
end

Correspondence.main(System.argv())
