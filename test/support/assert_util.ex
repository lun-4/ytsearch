defmodule YtSearch.AssertUtil do
  import ExUnit.Assertions

  def image(temporary_path) do
    {output, 0} = System.cmd("identify", [temporary_path])

    [{width, ""}, {height, ""}] =
      output
      |> String.split("PNG")
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
