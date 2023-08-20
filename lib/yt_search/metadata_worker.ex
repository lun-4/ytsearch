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
               id: youtube_id,
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
  def handle_info(:vibe_check, %{last_reply: last_reply} = state) do
    # if state.last_reply - now is over 60, exit
    # if not, schedule 60000

    now = System.monotonic_time(:second)
    time_since_last_reply = now - last_reply

    if time_since_last_reply > 60 do
      {:stop, {:shutdown, :intended_suicide}, state}
    else
      # schedule next exit if we arent supposed to die yet
      schedule_deffered_exit()
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:fetch, _from, state) do
    new_state =
      state
      |> fetch_data

    {:reply, new_state.metadata, new_state}
  end
end
