defmodule YtSearch.ChaptersCleanerTest do
  use YtSearch.DataCase, async: false
  import Ecto.Query
  alias YtSearch.Chapters
  alias YtSearch.Data.ChapterRepo

  test "it removes expired chapters and keeps fresh ones" do
    expired = Chapters.insert("expiredchapt", [%{"title" => "old"}])
    fresh = Chapters.insert("freshchapter", [%{"title" => "new"}])

    from(s in Chapters, where: s.youtube_id == ^expired.youtube_id)
    |> ChapterRepo.update_all(
      set: [
        inserted_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-Chapters.ttl_seconds() - 30_000)
          |> NaiveDateTime.truncate(:second)
      ]
    )

    assert Chapters.Cleaner.tick() == 1

    assert Chapters.fetch(expired.youtube_id) == nil
    assert Chapters.fetch(fresh.youtube_id).chapter_data == fresh.chapter_data
  end
end
