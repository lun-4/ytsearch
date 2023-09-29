defmodule YtSearch.Factory do
  # with Ecto
  use ExMachina.Ecto, repo: YtSearch.Repo

  def slot_factory do
    {:ok, id} = YtSearch.SlotUtilities.generate_id_v3(YtSearch.Slot)

    %YtSearch.Slot{
      id: id,
      youtube_id: sequence("youtube"),
      video_duration: 300,
      used_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      expires_at:
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(60, :second)
        |> NaiveDateTime.truncate(:second),
      keepalive: false
    }
  end
end
