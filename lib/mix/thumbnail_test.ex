defmodule Mix.Tasks.YtSearch.TestThumbnail do
  use Mix.Task

  @mogrify false

  def run([path]) do
    if @mogrify do
      temporary_path = Temp.path!()
      File.write(temporary_path, File.read!(path))

      Mogrify.open(temporary_path)
      |> Mogrify.resize("256x144")
      |> Mogrify.gravity("center")
      |> Mogrify.custom("background", "none")
      |> Mogrify.extent("256x144")
      |> Mogrify.save(in_place: true)
      |> dbg

      IO.inspect(temporary_path)
    else
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
      |> Image.write!("output.webp")
      |> dbg
    end
  end
end
