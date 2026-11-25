#!/usr/bin/env elixir
# VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# See the LICENSE file for the full text.

# tests/program_to_text.exs -- Render a lowered program XML as
# instruction text, one instruction per line.
#
# Usage:
#   elixir tests/program_to_text.exs PROGRAM.xml
#
# Each <instruction opcode="OP">operand</instruction> becomes `OP` or
# `OP operand`, the same form Lean's `instrToText` prints in
# tests/lean-cross-check.lean. The pipeline diffs this output against
# the Lean compiler's output, so the form must match exactly.

defmodule ProgramToText do
  def main([path]) do
    xml = File.read!(path)
    {doc, _} = :xmerl_scan.string(String.to_charlist(xml))
    doc |> instructions() |> Enum.each(&IO.puts/1)
  end

  def main(_), do: usage_error()

  defp usage_error do
    IO.puts(:stderr, "usage: elixir tests/program_to_text.exs PROGRAM.xml")
    System.halt(2)
  end

  defp instructions({:xmlElement, :program, _, _, _, _, _, _, content, _, _, _}) do
    content
    |> Enum.filter(&match?({:xmlElement, :instruction, _, _, _, _, _, _, _, _, _, _}, &1))
    |> Enum.map(fn {:xmlElement, :instruction, _, _, _, _, _, attrs, content, _, _, _} ->
      opcode = attr(attrs, :opcode)
      text = text_content(content)

      if text == "" do
        opcode
      else
        opcode <> " " <> text
      end
    end)
  end

  defp instructions(_), do: raise("program_to_text: root element is not <program>")

  defp attr(attrs, name) do
    case Enum.find(attrs, fn {:xmlAttribute, n, _, _, _, _, _, _, _, _} -> n == name end) do
      {:xmlAttribute, _, _, _, _, _, _, _, value, _} -> List.to_string(value)
      nil -> raise "program_to_text: <instruction> without #{name} attribute"
    end
  end

  defp text_content(content) do
    content
    |> Enum.filter(&match?({:xmlText, _, _, _, _, _}, &1))
    |> Enum.map(fn {:xmlText, _, _, _, value, _} -> List.to_string(value) end)
    |> Enum.join("")
  end
end

ProgramToText.main(System.argv())
