defmodule YtSearchWeb.ThumbnailTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock

  alias YtSearch.Youtube
  alias YtSearch.Thumbnail

  defp png_data do
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVQYV2NgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII="
    |> Base.decode64!()
  end

  test "correctly thumbnails a youtube thumbnail", %{conn: conn} do
    with_mock(
      HTTPoison,
      get!: fn _ ->
        %HTTPoison.Response{
          body: png_data(),
          headers: [{"content-type", "image/png"}],
          status_code: 200
        }
      end
    ) do
      {:ok, thumb} = Youtube.Thumbnail.maybe_download_thumbnail("a", "http://youtube.com")
      assert thumb.id == "a"
      repo_thumb = Thumbnail.fetch("a")
      assert repo_thumb.id == thumb.id
      # TODO verify dimensions of given repo thumb
    end
  end
end
