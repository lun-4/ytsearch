defmodule YtSearchWeb.ThumbnailTest do
  use YtSearchWeb.ConnCase, async: false

  alias YtSearch.Youtube
  alias YtSearch.Thumbnail
  alias YtSearch.Slot
  alias YtSearch.SlotUtilities
  alias YtSearch.Data.ThumbnailRepo

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
    File.write!(temporary_path, Thumbnail.blob(repo_thumb))
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
    |> ThumbnailRepo.update!()

    fetched = Thumbnail.fetch(@youtube_id)
    assert Thumbnail.blob(fetched) == Thumbnail.blob(thumb)
    assert Thumbnail.Janitor.tick() > 0
    nil = Thumbnail.fetch(@youtube_id)
  end

  test "janitor removes only expired thumbnails and their files" do
    expired = Thumbnail.insert("expired_thumb", "image/png", Data.png(), [])
    _fresh = Thumbnail.insert("fresh_thumb", "image/png", Data.png(), [])
    kept_alive = Thumbnail.insert("keepalive_thumb", "image/png", Data.png(), keepalive: true)

    [expired, kept_alive]
    |> Enum.each(fn thumb ->
      thumb
      |> Ecto.Changeset.change(
        expires_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-10, :second)
          |> NaiveDateTime.truncate(:second)
      )
      |> ThumbnailRepo.update!()
    end)

    assert Thumbnail.Janitor.tick() == 1

    assert Thumbnail.fetch("expired_thumb") == nil
    refute File.exists?(Thumbnail.path_for("expired_thumb"))

    assert Thumbnail.fetch("fresh_thumb") != nil
    assert File.exists?(Thumbnail.path_for("fresh_thumb"))

    # keepalive passes strict TTL even when expired, and the janitor spares it
    assert Thumbnail.fetch("keepalive_thumb") != nil
    assert File.exists?(Thumbnail.path_for("keepalive_thumb"))
  end

  test "thumbnails are refreshed" do
    thumb = Thumbnail.insert(@youtube_id, "image/png", Data.png(), [])

    thumb
    |> Ecto.Changeset.change(
      used_at:
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-180, :second)
        |> NaiveDateTime.truncate(:second),
      expires_at:
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-10, :second)
        |> NaiveDateTime.truncate(:second)
    )
    |> ThumbnailRepo.update!()

    fetched = Thumbnail.fetch(@youtube_id)
    assert Thumbnail.blob(fetched) == Thumbnail.blob(thumb)

    fetched
    |> SlotUtilities.refresh_expiration()

    fetched2 = Thumbnail.fetch(@youtube_id)
    assert Thumbnail.blob(fetched2) == Thumbnail.blob(thumb)
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
      |> get(~p"/api/v6/tn/#{slot.id}")

    assert conn.status == 200
  end
end
