defmodule Mix.Tasks.YtSearch.TestThumbnail do
  use Mix.Task

  def run([path]) do
    input_image = Image.open!(path)

    input_image
    |> Image.add_alpha(:transparent)
    |> then(fn
      {:ok, image} ->
        image

      {:error, "Image already has an alpha band"} ->
        input_image

      {:error, err} ->
        raise err
    end)
    |> Image.thumbnail!(256, height: 144)
    |> Image.embed!(256, 144, background_transparency: 0, x: :center, y: :center)
    |> Image.write!("output.png")
    |> dbg
  end
end
