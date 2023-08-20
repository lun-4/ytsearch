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
end
