defmodule YtSearch.Trending do
  @moduledoc """
  Tracks video views via PubSub and logs them.

  Future: Will use this data to build a trending videos feature.
  """

  use GenServer
  require Logger

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to slot_view events via Phoenix.PubSub (works across distributed nodes)
    Phoenix.PubSub.subscribe(YtSearch.PhoenixPubSub, "slot_view")

    Logger.info("Trending tracker started and subscribed to slot_view")

    {:ok, %{}}
  end

  @impl true
  def handle_info({:slot_view, %YtSearch.Slot{} = slot}, state) do
    Logger.debug("Slot viewed: #{slot.youtube_id} (slot_id: #{slot.id})")

    # Increment view count in video_counter table
    # Using INSERT OR REPLACE to atomically increment the counter
    YtSearch.Data.TrendingRepo.query!("""
      INSERT INTO video_counter (yt_video_id, view_count)
      VALUES (?, 1)
      ON CONFLICT(yt_video_id) DO UPDATE SET
        view_count = view_count + 1
    """, [slot.youtube_id])

    {:noreply, state}
  end
end
