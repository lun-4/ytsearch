defmodule Mix.Tasks.YtSearch.TestThumbnail do
  use Mix.Task

  def run([path]) do
    Image.open!(path)
    |> Image.add_alpha!(:transparent)
    |> Image.thumbnail!(256, height: 144)
    |> Image.embed!(256, 144, background_transparency: 0, x: :center, y: :center)
    |> Image.write!("output.png")
    |> dbg
  end
end
