#!/usr/bin/env elixir
# tests/check_dtd.exs -- Validate vanish XML against the SGML DTD structure.
#
# Usage:
#   elixir tests/check_dtd.exs sgml/vanish.dtd FILE.xml [FILE.xml ...]
#
# The DTD (sgml/vanish.dtd) is written in SGML form with `- -`
# minimization markers. This worker parses its ELEMENT declarations
# and validates each XML document against the declared content models:
#   vanish  -> (expr)
#   expr    -> (sub|add|mul|pow|symbol|integer)
#   sub|add|mul|pow -> (expr, expr)
#   symbol|integer  -> (#PCDATA)
# A document that fails any rule is reported and the worker exits
# non-zero. This is the G_grammar gate of the admission test.

defmodule CheckDtd do
  def main([dtd_path | files]) when files != [] do
    models = parse_dtd(File.read!(dtd_path))
    failures =
      Enum.flat_map(files, fn file ->
        case validate_file(file, models) do
          :ok -> []
          {:error, reason} -> ["#{file}: #{reason}"]
        end
      end)

    if failures == [] do
      IO.puts("check_dtd: all #{length(files)} file(s) validate against #{dtd_path}")
    else
      Enum.each(failures, &IO.puts(:stderr, "FAIL: #{&1}"))
      System.halt(1)
    end
  end

  def main(_), do: usage_error()

  defp usage_error do
    IO.puts(:stderr, "usage: elixir tests/check_dtd.exs sgml/vanish.dtd FILE.xml [FILE.xml ...]")
    System.halt(2)
  end

  # <!ELEMENT vanish - - (expr)>  ->  {:vanish, {:seq, [:expr]}}
  defp parse_dtd(dtd) do
    Regex.scan(~r/<!ELEMENT\s+(\S+)\s+-+\s+-+\s+\(([^)]*)\)>/, dtd)
    |> Map.new(fn [_, name, model] ->
      {String.to_atom(name), parse_model(String.trim(model))}
    end)
  end

  defp parse_model("#PCDATA"), do: :pcdata
  defp parse_model(model) do
    cond do
      String.contains?(model, "|") ->
        {:choice, model |> String.split("|") |> Enum.map(&String.trim/1) |> Enum.map(&String.to_atom/1)}

      String.contains?(model, ",") ->
        {:seq, model |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&String.to_atom/1)}

      true ->
        {:seq, [String.to_atom(model)]}
    end
  end

  defp validate_file(file, models) do
    xml = File.read!(file)
    {doc, _} = :xmerl_scan.string(String.to_charlist(xml))
    validate_element(doc, :vanish, models)
  rescue
    e -> {:error, "unparsable XML: #{Exception.message(e)}"}
  end

  defp validate_element({:xmlElement, name, _, _, _, _, _, _, content, _, _, _}, expected, models) do
    cond do
      name != expected ->
        {:error, "expected <#{expected}> element, found <#{name}>"}

      true ->
        case Map.fetch(models, name) do
          :error -> {:error, "element <#{name}> is not declared in the DTD"}
          {:ok, model} -> validate_model(model, element_children(content), models)
        end
    end
  end

  defp validate_element(other, expected, _models) do
    {:error, "expected <#{expected}> element, found #{inspect(other)}"}
  end

  defp validate_model(:pcdata, children, _models) do
    if children == [], do: :ok, else: {:error, "element with #PCDATA content must not contain child elements"}
  end

  defp validate_model({:seq, wanted}, children, models) do
    if Enum.map(children, &elem(&1, 1)) == wanted do
      Enum.reduce_while(children, :ok, fn child, _ ->
        case validate_element(child, elem(child, 1), models) do
          :ok -> {:cont, :ok}
          err -> {:halt, err}
        end
      end)
    else
      {:error,
       "child elements #{inspect(Enum.map(children, &elem(&1, 1)))} do not match content model (#{Enum.join(wanted, ", ")})"}
    end
  end

  defp validate_model({:choice, allowed}, [child], models) do
    if elem(child, 1) in allowed do
      validate_element(child, elem(child, 1), models)
    else
      {:error, "child element <#{elem(child, 1)}> is not one of (#{Enum.join(allowed, "|")})"}
    end
  end

  defp validate_model({:choice, allowed}, children, _models) do
    {:error,
     "expected exactly one child element from (#{Enum.join(allowed, "|")}), found #{length(children)}"}
  end

  # Element children only; whitespace-only text between elements is ignored.
  defp element_children(content) do
    Enum.filter(content, &match?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}, &1))
  end
end

CheckDtd.main(System.argv())
