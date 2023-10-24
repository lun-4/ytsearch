defmodule YtSearchWeb.ThumbnailTest do
  use YtSearchWeb.ConnCase, async: false

  alias YtSearch.Youtube
  alias YtSearch.Thumbnail
  alias YtSearch.Slot
  alias YtSearch.Repo
  alias YtSearch.SlotUtilities

  alias YtSearch.Test.Data

  setup do
    Data.default_global_mock()
  end

  test "correctly thumbnails a youtube thumbnail" do
    {:ok, thumb} = Youtube.Thumbnail.maybe_download_thumbnail("a", "https://i.ytimg.com", [])
    assert thumb.id == "a"
    repo_thumb = Thumbnail.fetch("a")
    assert repo_thumb.id == thumb.id

    temporary_path = Temp.path!()
    File.write!(temporary_path, repo_thumb.data)
    YtSearch.AssertUtil.image(temporary_path)
  end

  @youtube_id "Amongus"

  test "thumbnails are cleaned when theyre too old", _ctx do
    thumb = Thumbnail.insert(@youtube_id, "image/png", Data.png(), [])

    thumb
    |> Ecto.Changeset.change(
      expires_at:
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-10, :second)
        |> NaiveDateTime.truncate(:second)
    )
    |> Repo.update!()

    fetched = Thumbnail.fetch(@youtube_id)
    assert fetched.data == thumb.data
    assert Thumbnail.Janitor.tick() > 0
    nil = Thumbnail.fetch(@youtube_id)
  end

  test "thumbnails are refreshed" do
    thumb = Thumbnail.insert(@youtube_id, "image/png", Data.png(), [])

    thumb
    |> Ecto.Changeset.change(
      expires_at:
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-10, :second)
        |> NaiveDateTime.truncate(:second)
    )
    |> Repo.update!()

    fetched = Thumbnail.fetch(@youtube_id)
    assert fetched.data == thumb.data

    fetched
    |> SlotUtilities.refresh_expiration()

    fetched2 = Thumbnail.fetch(@youtube_id)
    assert fetched2.data == thumb.data
    assert NaiveDateTime.compare(fetched2.expires_at, fetched.expires_at) == :gt

    Thumbnail.Janitor.tick()
    assert Thumbnail.fetch(@youtube_id) != nil
  end

  test "fetches thumbnails for a single slot id", %{conn: conn} do
    slot = Slot.create(@youtube_id, 3600)

    {:ok, thumb} =
      Youtube.Thumbnail.maybe_download_thumbnail(@youtube_id, "https://i.ytimg.com", [])

    assert thumb.id == @youtube_id

    conn =
      conn
      |> get(~p"/api/v4/tn/#{slot.id}")

    assert conn.status == 200
  end
end
