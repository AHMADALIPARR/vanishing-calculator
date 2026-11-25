#!/usr/bin/env elixir
# tests/xslt.exs -- XSLT 1.0 driver for the vanish-lisp pipeline.
#
# Runs a stylesheet through libxslt (via the `xsltproc` binary, the
# same XSLT 1.0 engine lxml fronts) and writes the result to stdout.
#
# Usage:
#   elixir tests/xslt.exs STYLESHEET INPUT [name=value ...]
#
# Stylesheet parameters are passed as --stringparam, exactly as the
# pipeline invokes them. Exits non-zero when xsltproc fails, printing
# its diagnostic to stderr. The transform itself is unchanged: the
# stylesheets under xslt/ and openmath/ are the transformation.

defmodule Xslt do
  def main([stylesheet, input | params]) do
    args =
      Enum.flat_map(params, fn param ->
        case String.split(param, "=", parts: 2) do
          [name, value] -> ["--stringparam", name, value]
          _ -> usage_error("bad parameter #{inspect(param)} (want name=value)")
        end
      end) ++ [stylesheet, input]

    case System.cmd("xsltproc", args, stderr_to_stdout: false) do
      {output, 0} ->
        IO.binwrite(:stdio, output)

      {output, code} ->
        IO.binwrite(:stderr, output)
        IO.puts(:stderr, "xslt.exs: xsltproc failed (exit #{code})")
        System.halt(1)
    end
  end

  def main(_), do: usage_error("usage: elixir tests/xslt.exs STYLESHEET INPUT [name=value ...]")

  defp usage_error(msg) do
    IO.puts(:stderr, msg)
    System.halt(2)
  end
end

Xslt.main(System.argv())
