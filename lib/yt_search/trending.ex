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
    # Subscribe to slot_view events
    :ok = YtSearch.PubSub.subscribe(:slot_view)

    Logger.info("Trending tracker started and subscribed to :slot_view")

    {:ok, %{}}
  end

  @impl true
  def handle_info({:pubsub, :slot_view, slot}, state) do
    Logger.debug("Slot viewed: #{slot.youtube_id} (slot_id: #{slot.id})")

    {:noreply, state}
  end
end
