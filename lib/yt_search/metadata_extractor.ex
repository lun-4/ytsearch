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

  def sponsorblock_segments(youtube_id) when is_binary(youtube_id) do
    worker = worker_for(:sponsorblock_segments, youtube_id)
    sponsorblock_segments(worker)
  end

  def sponsorblock_segments(worker) when is_pid(worker) do
    GenServer.call(worker, :sponsorblock_segments, @default_timeout)
  end

  def mp4_link(youtube_id) when is_binary(youtube_id) do
    worker = worker_for(:mp4_link, youtube_id)
    mp4_link(worker)
  end

  def mp4_link(worker) when is_pid(worker) do
    GenServer.call(worker, :mp4_link, @default_timeout)
  end

  def worker_for(type, youtube_id) when type in [:subtitles, :mp4_link, :sponsorblock_segments] do
    worker =
      case DynamicSupervisor.start_child(
             YtSearch.MetadataSupervisor,
             %{
               id: __MODULE__,
               restart: :transient,
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
    schedule_deffered_exit()

    {:ok,
     %{
       type: type,
       youtube_id: youtube_id,
       mp4_link: nil,
       subtitle: nil,
       last_reply: System.monotonic_time(:second),
       will_die?: false
     }}
  end

  @impl true
  def handle_call(t, from, state) when t in [:mp4_link, :subtitles, :sponsorblock_segments] do
    handle_request(t, from, state)
  end

  @impl true
  @doc "this should only be called in tests"
  def handle_call(:unregister, _from, %{type: type, youtube_id: youtube_id} = state) do
    if Mix.env() == :test do
      Registry.unregister(YtSearch.MetadataExtractors, {type, youtube_id})
    else
      raise "unregister is an invalid call on non-test environments"
    end

    {:reply, :ok, state}
  end

  defp schedule_deffered_exit() do
    Process.send_after(self(), :vibe_check, 60000 + Enum.random(2000..20000))
  end

  @impl true
  def handle_info(
        :vibe_check,
        %{type: type, youtube_id: youtube_id, last_reply: last_reply} = state
      ) do
    # if state.last_reply - now is over 30, exit
    # if not, schedule 30000

    now = System.monotonic_time(:second)
    time_since_last_reply = now - last_reply

    new_state =
      if time_since_last_reply > 60 do
        Registry.unregister(YtSearch.MetadataExtractors, {type, youtube_id})

        Process.send_after(self(), {:suicide, last_reply}, 30000 + Enum.random(2000..20000))
        state |> Map.put(:will_die?, true)
      else
        # schedule next exit if we arent supposed to die yet
        schedule_deffered_exit()
        state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:suicide, last_reply}, %{last_reply: new_last_reply} = state) do
    {:message_queue_len, queue_length} = Process.info(self(), :message_queue_len)

    if queue_length > 0 do
      Logger.error(
        "#{inspect(self())}: stopping yet message queue len is #{queue_length}, shouldn't happen. #{inspect(state)}"
      )
    end

    if last_reply != new_last_reply do
      Logger.error(
        "#{inspect(self())}: intended_suicide but last_reply got updated. was #{last_reply}, is not #{new_last_reply}"
      )
    end

    {:stop, {:shutdown, :intended_suicide}, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.warning(
      "PROBE: Extractor Terminate. self=#{inspect(self())}, reason=#{inspect(reason)} state=#{inspect(state)}"
    )
  end

  defp process_metadata(meta, %{youtube_id: youtube_id, type: :mp4_link} = _state) do
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

    if wanted_video_result != nil do
      url = wanted_video_result["url"]
      uri = url |> URI.parse()
      expiry_timestamp = Youtube.expiry_from_uri(uri)

      link =
        YtSearch.Mp4Link.insert(
          youtube_id,
          url |> Youtube.unproxied_piped_url(),
          expiry_timestamp,
          wanted_video_result
        )

      {:ok, link}
    else
      Logger.warning("no valid formats found for #{youtube_id}")
      {:error, :no_valid_video_formats_found}
    end
  end

  defp process_metadata(meta, %{youtube_id: youtube_id, type: :subtitles} = _state) do
    with {:ok, subtitles} <- Youtube.extract_subtitles(meta) do
      {:ok,
       subtitles
       |> Enum.map(fn {subtitle, data} ->
         YtSearch.Subtitle.insert(youtube_id, subtitle["code"], data)
       end)}
    end
  end

  alias YtSearch.Sponsorblock.Segments

  defp process_metadata(
         _metadata,
         %{youtube_id: youtube_id, type: :sponsorblock_segments} = _state
       ) do
    with {:ok, response} <- Youtube.sponsorblock_segments(youtube_id),
         :ok <- is_actual_list(response) do
      {:ok, Segments.insert(youtube_id, response)}
    end
  end

  defp is_actual_list(response) do
    if is_list(response) do
      :ok
    else
      {:error, :not_a_list}
    end
  end

  defp process_error(error, %{youtube_id: youtube_id, type: :sponsorblock_segments} = _state) do
    Logger.error("failed to fetch sponsorblock_segments: #{inspect(error)}. setting it as nil")
    {:ok, Segments.insert(youtube_id, nil)}
  end

  defp process_error(error, %{youtube_id: youtube_id, type: :subtitles} = _state) do
    Logger.error("failed to fetch subtitles: #{inspect(error)}. setting it as not found")
    YtSearch.Subtitle.insert(youtube_id, "notfound", nil)
    {:ok, []}
  end

  defp process_error(error, %{youtube_id: youtube_id, type: :mp4_link} = _state) do
    Logger.error("failed to fetch link: #{inspect(error)}.")

    case error do
      {:error, err} ->
        {:error, YtSearch.Mp4Link.insert_error(youtube_id, err)}

      _ ->
        Logger.error(
          "an error happened while fetching link. #{inspect(error)}, using internal_error reason"
        )

        {:error, YtSearch.Mp4Link.insert_error(youtube_id, :internal_error)}
    end
  end

  defp handle_request(request_type, _from, %{will_die?: will_die?} = state) do
    if will_die? do
      Logger.error(
        "#{inspect(self())}: should not be replying to clients when worker is going to die"
      )
    end

    if request_type == state.type do
      new_state =
        state
        |> Map.put(:last_reply, System.monotonic_time(:second))

      result = state[state.type]

      if result != nil do
        {:reply, result, new_state}
      else
        with {:ok, meta} <- YtSearch.Metadata.Worker.fetch_for(state.youtube_id),
             {:ok, result} <- process_metadata(meta, state) do
          # TODO remove copypaste
          new_state =
            new_state
            |> Map.put(state.type, {:ok, result})

          {:reply, {:ok, result}, new_state}
        else
          value ->
            reply = process_error(value, state)

            new_state =
              new_state
              |> Map.put(state.type, reply)

            {:reply, reply, new_state}
        end
      end
    else
      {:reply, {:error, :wrong_worker_type}, state}
    end
  end
end
