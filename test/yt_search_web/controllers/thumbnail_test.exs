defmodule YtSearchWeb.ThumbnailTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock

  alias YtSearch.Youtube
  alias YtSearch.Thumbnail
  import Ecto.Query
  alias YtSearch.Repo

  defp png_data do
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVQYV2NgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII="
    |> Base.decode64!()
  end

  test "correctly thumbnails a youtube thumbnail" do
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

      temporary_path = Temp.path!()
      File.write!(temporary_path, repo_thumb.data)
      YtSearch.AssertUtil.image(temporary_path)
    end
  end

  @youtube_id "Amongus"

  test "thumbnails are cleaned when theyre too old", _ctx do
    thumb = Thumbnail.insert(@youtube_id, "image/png", png_data())

    from(t in Thumbnail, where: t.id == ^thumb.id, select: t)
    |> Repo.update_all(
      set: [
        inserted_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-Thumbnail.ttl_seconds() - 2)
      ]
    )

    fetched = Thumbnail.fetch(@youtube_id)
    assert fetched.data == thumb.data
    Thumbnail.Janitor.tick()
    nil = Thumbnail.fetch(@youtube_id)
  end
end
