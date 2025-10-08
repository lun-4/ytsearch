defmodule YtSearch.AssertUtil do
  import ExUnit.Assertions

  def image(temporary_path, wanted_width \\ 8) do
    {output, 0} = System.cmd("identify", [temporary_path])

    assert String.contains?(output, "#{wanted_width}-bit")

    split_word =
      cond do
        String.contains?(output, "PNG") -> "PNG"
        String.contains?(output, "WEBP") -> "WEBP"
        true -> raise "invalid output: #{output}"
      end

    [{width, ""}, {height, ""}] =
      output
      |> String.split(split_word)
      |> Enum.at(1)
      |> String.trim(" ")
      |> String.split(" ")
      |> Enum.at(0)
      |> String.split("x")
      |> Enum.map(&Integer.parse(&1, 10))

    assert is_integer(width)
    assert is_integer(height)

    assert width > 0
    assert height > 0
  end

  def strip_unique_values(m), do: m |> Map.delete("__x_request_id") |> Map.delete("__time")

  def equal_search_responses(rjson1, rjson2) do
    assert rjson1 |> strip_unique_values() ==
             rjson2 |> strip_unique_values()
  end
end
