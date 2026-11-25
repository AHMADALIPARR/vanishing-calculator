#!/usr/bin/env elixir
# tests/check_dump.exs -- Check the ELF loader round-trip.
#
# Usage:
#   elixir tests/check_dump.exs DUMP CANON.xml
#
# The loader's --dump output carries the AST between the
# "--- ast ---" and "--- proof ---" markers. That section, stripped,
# must equal the canonical vanish XML, stripped. This is part of the
# G_binary gate of the admission test.

defmodule CheckDump do
  def main([dump_path, canon_path]) do
    dump = File.read!(dump_path)
    canon = File.read!(canon_path) |> String.trim()

    case extract_ast(dump) do
      {:ok, ast} when ast == canon ->
        IO.puts("check_dump: loader round-trip reconstructs the identical AST")

      {:ok, _ast} ->
        IO.puts(:stderr, "check_dump: dumped AST differs from the canonical XML")
        System.halt(1)

      :error ->
        IO.puts(:stderr, "check_dump: dump is missing the --- ast --- / --- proof --- markers")
        System.halt(1)
    end
  end

  def main(_), do: usage_error()

  defp usage_error do
    IO.puts(:stderr, "usage: elixir tests/check_dump.exs DUMP CANON.xml")
    System.halt(2)
  end

  defp extract_ast(dump) do
    with [_, rest] <- String.split(dump, "--- ast ---", parts: 2),
         [ast, _] <- String.split(rest, "--- proof ---", parts: 2) do
      {:ok, String.trim(ast)}
    else
      _ -> :error
    end
  end
end

CheckDump.main(System.argv())
