defmodule YtSearch.Metadata.Worker do
  use GenServer

  require Logger
  alias YtSearch.Youtube

  def start_link(youtube_id, opts \\ []) do
    GenServer.start_link(__MODULE__, youtube_id, opts)
  end

  @default_timeout 15000

  def fetch_for(youtube_id) do
    worker =
      case DynamicSupervisor.start_child(
             YtSearch.MetadataSupervisor,
             %{
               id: __MODULE__,
               start:
                 {__MODULE__, :start_link,
                  [
                    youtube_id,
                    [name: {:via, Registry, {YtSearch.MetadataWorkers, youtube_id, :self}}]
                  ]}
             }
           ) do
        {:ok, worker} ->
          worker

        {:error, {:already_started, worker}} ->
          worker
      end

    GenServer.call(worker, :fetch, @default_timeout)
  end

  @impl true
  def init(youtube_id) do
    schedule_deffered_exit()
    {:ok, %{youtube_id: youtube_id, metadata: nil, last_reply: System.monotonic_time(:second)}}
  end

  defp fetch_data(%{metadata: meta, youtube_id: youtube_id} = state) do
    if meta == nil do
      response = Youtube.video_metadata(youtube_id)
      %{state | metadata: response}
    else
      state
    end
  end

  defp schedule_deffered_exit() do
    Process.send_after(self(), :vibe_check, 60000)
  end

  @impl true
  def handle_info(:vibe_check, %{youtube_id: youtube_id, last_reply: last_reply} = state) do
    # if state.last_reply - now is over 60, schedule a future exit in 60 seconds
    # if not, schedule 60000

    now = System.monotonic_time(:second)
    time_since_last_reply = now - last_reply

    if time_since_last_reply > 60 do
      Registry.unregister(YtSearch.MetadataWorkers, youtube_id)
      Process.send_after(self(), :suicide, 30000)
    else
      # schedule next exit if we arent supposed to die yet
      schedule_deffered_exit()
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:suicide, state) do
    {:stop, {:shutdown, :intended_suicide}, state}
  end

  @impl true
  def handle_call(:fetch, _from, state) do
    new_state =
      state
      |> fetch_data

    {:reply, new_state.metadata, new_state}
  end

  @doc "this should only be called in tests"
  def handle_call(:unregister, _from, %{youtube_id: youtube_id} = state) do
    if Mix.env() == :test do
      Registry.unregister(YtSearch.MetadataWorkers, youtube_id)
    else
      raise "unregister is an invalid call on non-test environments"
    end

    {:reply, :ok, state}
  end
end
