#!/usr/bin/env elixir
# VANISH-LISP — Copyright (c) 2026 VANISH-LISP Contributors
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# See the LICENSE file for the full text.

# tests/check_om.exs -- Check an OpenMath round-trip.
#
# Usage:
#   elixir tests/check_om.exs ROUNDTRIP.om ORIGINAL.om
#
# Accepts the round-trip OpenMath when it is either identical to the
# original, or the `vanishes()` wrapping of it: the <vanish> root is
# itself the vanishing claim, so a bare expression comes back wrapped
# in <OMS cd="vanish1" name="vanishes"/>. Anything else is a failure.
# This is part of the G_semantics gate of the admission test.

defmodule CheckOm do
  def main([rt_path, orig_path]) do
    rt = parse(File.read!(rt_path))
    orig = parse(File.read!(orig_path))

    cond do
      rt == orig ->
        IO.puts("check_om: round-trip OpenMath is identical")

      vanishes_wrapping?(rt, orig) ->
        IO.puts("check_om: round-trip OpenMath is the vanishes() wrapping")

      true ->
        IO.puts(:stderr, "check_om: round-trip OpenMath matches neither the original nor its vanishes() wrapping")
        System.halt(1)
    end
  end

  def main(_), do: usage_error()

  defp usage_error do
    IO.puts(:stderr, "usage: elixir tests/check_om.exs ROUNDTRIP.om ORIGINAL.om")
    System.halt(2)
  end

  # Normalized tree: {name, sorted_attrs, children}; whitespace-only
  # text nodes are dropped so formatting never affects the comparison.
  defp parse(xml) do
    {doc, _} = :xmerl_scan.string(String.to_charlist(xml))
    normalize(doc)
  end

  defp normalize({:xmlElement, name, _, _, _, _, _, attrs, content, _, _, _}) do
    norm_attrs =
      attrs
      |> Enum.map(fn {:xmlAttribute, n, _, _, _, _, _, _, v, _} -> {n, List.to_string(v)} end)
      |> Enum.sort()

    norm_children =
      content
      |> Enum.map(&normalize/1)
      |> Enum.reject(&(&1 == :blank))

    {name, norm_attrs, norm_children}
  end

  defp normalize({:xmlText, _, _, _, value, _}) do
    text = List.to_string(value)
    if String.trim(text) == "", do: :blank, else: {:text, text}
  end

  defp normalize(other), do: {:other, inspect(other)}

  defp vanishes_wrapping?({:OMOBJ, _, [oma]}, {:OMOBJ, _, [inner]}) do
    case oma do
      {:OMA, _, [{:OMS, [{:cd, "vanish1"}, {:name, "vanishes"}], []}, wrapped]} -> wrapped == inner
      _ -> false
    end
  end

  defp vanishes_wrapping?(_, _), do: false
end

CheckOm.main(System.argv())
