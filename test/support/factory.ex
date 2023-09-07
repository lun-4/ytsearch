defmodule YtSearch.Factory do
  # with Ecto
  use ExMachina.Ecto, repo: YtSearch.Repo

  def slot_factory do
    {:ok, id} = YtSearch.SlotUtilities.find_available_slot_id(YtSearch.Slot)

    %YtSearch.Slot{
      id: id,
      youtube_id: sequence("youtube"),
      title: sequence("title"),
      video_duration: 300
    }
  end
end
