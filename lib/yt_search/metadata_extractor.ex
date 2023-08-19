defmodule YtSearch.MetadataExtractor.Worker do
  use GenServer
  require Logger

  alias YtSearch.Youtube

  def start_link(type, youtube_id, opts \\ []) do
    if String.starts_with?(youtube_id, "https://") do
      raise "invalid youtube id: #{youtube_id}"
    end

    GenServer.start_link(__MODULE__, {type, youtube_id}, opts)
  end

  @default_timeout 10000

  def subtitles(youtube_id) when is_binary(youtube_id) do
    worker = worker_for(:subtitles, youtube_id)
    subtitles(worker)
  end

  def subtitles(worker) when is_pid(worker) do
    GenServer.call(worker, :subtitles, @default_timeout)
  end

  def mp4_link(youtube_id) when is_binary(youtube_id) do
    worker = worker_for(:mp4_link, youtube_id)
    mp4_link(worker)
  end

  def mp4_link(worker) when is_pid(worker) do
    GenServer.call(worker, :mp4_link, @default_timeout)
  end

  def worker_for(type, youtube_id) when type in [:subtitles, :mp4_link] do
    worker =
      case DynamicSupervisor.start_child(
             YtSearch.MetadataSupervisor,
             %{
               id: {type, youtube_id},
               start:
                 {__MODULE__, :start_link,
                  [
                    type,
                    youtube_id,
                    [
                      name:
                        {:via, Registry, {YtSearch.MetadataExtractors, {type, youtube_id}, :self}}
                    ]
                  ]}
             }
           ) do
        {:ok, worker} ->
          worker

        {:error, {:already_started, worker}} ->
          worker
      end

    worker
  end

  @impl true
  def init({type, youtube_id}) do
    {:ok, %{type: type, youtube_id: youtube_id, mp4_link: nil, subtitle: nil}}
  end

  @impl true
  def handle_call(:mp4_link, from, state) do
    handle_request(:mp4_link, from, state)
  end

  @impl true
  def handle_call(:ping, from, state) do
    {:ok, :pong, state}
  end

  @impl true
  def handle_call(:subtitles, from, state) do
    handle_request(:subtitles, from, state)
  end

  defp schedule_deffered_exit() do
    Process.send_after(self(), :vibe_check, 60000)
  end

  @impl true
  def handle_info(:vibe_check, %{last_reply: last_reply} = state) do
    # if state.last_reply - now is over 30, exit
    # if not, schedule 30000

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

  defp process_metadata(meta, %{youtube_id: youtube_id, type: :mp4_link} = state) do
    wanted_video_result = Youtube.extract_valid_streams(meta["videoStreams"])

    #  override with hls
    wanted_video_result =
      if meta["livestream"] do
        %{
          "url" => meta["hls"]
        }
      else
        wanted_video_result
      end

    unless wanted_video_result == nil do
      url = wanted_video_result["url"]
      uri = url |> URI.parse()
      expiry_timestamp = Youtube.expiry_from_uri(uri)
      {:ok, {url |> Youtube.unproxied_piped_url(), expiry_timestamp, wanted_video_result}}
    else
      Logger.warning("no valid formats found for #{youtube_id}")
      {:error, :no_valid_video_formats_found}
    end
  end

  defp process_metadata(meta, %{youtube_id: youtube_id, type: :subtitles} = state) do
    with {:ok, subtitles} <- Youtube.extract_subtitles(meta) do
      subtitles
      |> Enum.each(fn {subtitle, data} ->
        YtSearch.Subtitle.insert(youtube_id, subtitle["code"], data)
      end)

      {:ok, :ok}
    end
  end

  defp process_error(error, %{youtube_id: youtube_id, type: :subtitles} = state) do
    Logger.error("failed to fetch subtitles: #{inspect(error)}. setting it as not found")
    YtSearch.Subtitle.insert(youtube_id, "notfound", nil)
    nil
  end

  defp process_error(error, %{type: :mp4_link} = state) do
    Logger.error("failed to fetch link: #{inspect(error)}.")
    error
  end

  defp handle_request(request_type, _from, state) do
    unless request_type != state.type do
      new_state =
        state
        |> Map.put(:last_reply, System.monotonic_time(:second))

      result = state[state.type]

      unless result == nil do
        {:reply, result, new_state}
      else
        schedule_deffered_exit()

        with {:ok, meta} <- YtSearch.Metadata.Worker.fetch_for(state.youtube_id),
             {:ok, result} <- process_metadata(meta, state) do
          {:reply, {:ok, result}, new_state}
        else
          {:error, _} = error ->
            reply = process_error(error, state)
            {:reply, reply, new_state}
        end
      end
    else
      {:reply, {:error, :wrong_worker_type}, state}
    end
  end
end