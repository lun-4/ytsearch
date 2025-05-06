defmodule YtSearch.Youtube do
  require Logger
  alias YtSearch.Youtube.Ratelimit
  alias YtSearch.Youtube.Latency
  alias YtSearch.Piped
  alias YtSearch.ChannelSlot
  alias YtSearch.PlaylistSlot

  defp piped() do
    Application.fetch_env!(:yt_search, YtSearch.Youtube)[:piped_url]
  end

  defp sponsorblock() do
    Application.fetch_env!(:yt_search, YtSearch.Youtube)[:sponsorblock_url]
  end

  defmodule CallCounter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_ytdlp_call_count,
        help: "Total times we requested the ytdlp path for calling ytdlp",
        labels: [:type]
      )

      Counter.declare(
        name: :yts_ytdlp_response,
        help: "responses from upstream youtube",
        labels: [:type, :status_code]
      )

      Counter.declare(
        name: :yts_ytdlp_search_results,
        help: "amount of results"
      )

      Counter.declare(
        name: :yts_ytdlp_search_requests,
        help: "amount of requests (for amount of results)"
      )
    end

    def inc(type) do
      Counter.inc(
        name: :yts_ytdlp_call_count,
        labels: [to_string(type)]
      )
    end

    def search_results(results) do
      Counter.inc(
        [name: :yts_ytdlp_search_requests],
        1
      )

      Counter.inc(
        [name: :yts_ytdlp_search_results],
        length(results)
      )
    end

    def response(type, result) do
      status_code =
        case result do
          {:ok, %Tesla.Env{} = response} ->
            response.status

          {:error, _} ->
            0
        end

      Counter.inc(
        name: :yts_ytdlp_response,
        labels: [to_string(type), status_code]
      )
    end
  end

  defmodule ErrorVideoCounter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_error_videos,
        help: "error video counter",
        labels: [:code]
      )
    end

    def inc(code) do
      Counter.inc(
        name: :yts_error_videos,
        labels: [to_string(code)]
      )
    end
  end

  defmodule UnavailableVideoCounter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_unavailable_video,
        help: "unavailable video counter",
        labels: [:code]
      )
    end

    def inc(code) do
      Counter.inc(
        name: :yts_unavailable_video,
        labels: [to_string(code)]
      )
    end
  end

  # vrcjson does not support unbalanced braces inside strings
  # this has been reported to vrchat already
  #
  # https://feedback.vrchat.com/vrchat-udon-closed-alpha-bugs/p/braces-inside-strings-in-vrcjson-can-fail-to-deserialize
  #
  # workaround for now is to strip off any brace character. we could write a balancer and strip
  # off the edge case, but i dont think i care enough to do that just for vrchat.

  def vrcjson_workaround(incoming_data, opts \\ []) do
    ignore_keys = Keyword.get(opts || [], :ignore_keys, [])

    case incoming_data do
      data when is_bitstring(data) ->
        data
        |> String.replace(~r/[\[\]{}]/, "")
        |> String.trim(" ")

      data when is_map(data) ->
        data
        |> Map.to_list()
        |> Enum.map(fn {key, value} ->
          if key in ignore_keys do
            {key, value}
          else
            {key, value |> vrcjson_workaround(opts)}
          end
        end)
        |> Map.new()

      data when is_list(data) ->
        data
        |> Enum.map(fn x -> vrcjson_workaround(x, opts) end)

      v when is_boolean(v) ->
        v

      nil ->
        nil

      v when is_atom(v) ->
        raise "Unsupported type #{inspect(v)}"

      v when is_tuple(v) ->
        raise "Unsupported type #{inspect(v)}"

      v ->
        v
    end
  end

  def videos_for(%ChannelSlot{youtube_id: channel_id}) do
    piped_search_call(
      :channel,
      &Piped.channel/2,
      &Piped.nextpage_channel/3,
      channel_id,
      fn x -> x["relatedStreams"] end,
      channel_result_limit(),
      []
    )
  end

  def videos_for(%PlaylistSlot{youtube_id: playlist_id}) do
    piped_search_call(
      :playlist,
      &Piped.playlists/2,
      &Piped.nextpage_playlists/3,
      playlist_id,
      fn x -> x["relatedStreams"] end,
      playlist_result_limit(),
      []
    )
  end

  @youtube_url_regex ~r/(www\.youtube\.com|youtube\.com|youtu\.be)\/(.+)$/
  @host_by_path ["youtu.be"]

  @keys_to_copy [
    "title",
    "uploader",
    "uploaderUrl",
    "isShort",
    "duration",
    "views",
    {"uploader", "uploaderName"},
    {"description", "shortDescription"},
    {"thumbnailUrl", "thumbnail"}
  ]

  def videos_for(text) when is_bitstring(text) do
    raise "do not use"
    captures = Regex.run(@youtube_url_regex, text)

    if captures != nil do
      [_full, host, url_path] = captures

      youtube_entity(host, url_path)
      |> resolve_youtube_entity
    else
      case Ratelimit.for_text_search() do
        :allow ->
          piped_search_call(
            :search,
            &Piped.search/2,
            &Piped.nextpage_search/3,
            text,
            fn x -> x["items"] end,
            result_limit(),
            []
          )

        :deny ->
          {:error, :overloaded_ytdlp_seats}
      end
    end
  end

  def fetch(text) when is_bitstring(text) do
    captures = Regex.run(@youtube_url_regex, text)

    if captures != nil do
      [_full, host, url_path] = captures

      youtube_entity(host, url_path)
      |> resolve_youtube_entity
    else
      case Ratelimit.for_text_search() do
        :allow ->
          do_a_search(
            :search,
            &Piped.search/2,
            text,
            fn x -> x["items"] end,
            fn x -> x["nextpage"] end,
            fn _ ->
              %{
                type: :text,
                title: text
              }
            end,
            result_limit()
          )

        :deny ->
          {:error, :overloaded_ytdlp_seats}
      end
    end
  end

  def fetch(%ChannelSlot{youtube_id: channel_id}) do
    do_a_search(
      :channel,
      &Piped.channel/2,
      channel_id,
      fn x -> x["relatedStreams"] end,
      fn x -> x["nextpage"] end,
      fn x ->
        %{
          type: :channel,
          title: x["name"]
        }
      end,
      channel_result_limit()
    )
  end

  def fetch(%PlaylistSlot{youtube_id: playlist_id}) do
    do_a_search(
      :playlist,
      &Piped.playlists/2,
      playlist_id,
      fn x -> x["relatedStreams"] end,
      fn x -> x["nextpage"] end,
      fn x ->
        %{
          type: :playlist,
          title: x["name"]
        }
      end,
      playlist_result_limit()
    )
  end

  def nextpage_fetch(%YtSearch.SearchSlot{type: :unfetched, nextpage_data: nextpage_data}) do
    do_a_search(
      :search,
      fn url, data ->
        %{"v" => 1, "t" => t, "q" => q, "n" => n} =
          data
          |> Jason.decode!()

        case t do
          "s" ->
            Piped.nextpage_search(url, q, n)

          "c" ->
            Piped.nextpage_channel(url, q, n)

          "p" ->
            Piped.nextpage_playlists(url, q, n)
        end
      end,
      nextpage_data,
      fn x -> x["items"] || x["relatedStreams"] end,
      fn x -> x["nextpage"] end,
      fn _ ->
        %{type: nil, title: nil}
      end,
      result_limit()
    )
  end

  def parse_url(text) when is_bitstring(text) do
    captures = Regex.run(@youtube_url_regex, text)

    if captures != nil do
      [_full, host, url_path] = captures

      youtube_entity(host, url_path)
    else
      nil
    end
  end

  def parse_url(_), do: nil

  defp youtube_entity(host, url_path) do
    case youtube_id_from_uri(host, url_path) do
      {:ok, youtube_id} ->
        {:video, youtube_id}

      {:input_error, _} ->
        case playlist_id_from_uri(host, url_path) do
          {:ok, playlist_id} ->
            {:playlist, playlist_id}

          {:input_error, _} = ev ->
            ev
        end
    end
  end

  defp playlist_id_from_uri(host, url_path) do
    uri = URI.parse(url_path)

    cond do
      String.starts_with?(uri.path, "playlist") ->
        if uri.query != nil do
          query =
            uri.query
            |> URI.decode_query()

          if query["list"] do
            {:ok, query["list"]}
          else
            Logger.error("invalid query params: #{inspect(query)}")
            {:input_error, :invalid_format}
          end
        else
          Logger.error("invalid /playlist uri: #{inspect(uri)}")
          {:input_error, :invalid_format}
        end

      true ->
        Logger.error("invalid uri path: #{host} #{url_path}")
        {:input_error, :invalid_format}
    end
  end

  defp resolve_youtube_entity({:video, youtube_id}) do
    with {:ok, piped_response} <- video_metadata(youtube_id) do
      raw_upload_date = piped_response["uploadDate"]

      video_result =
        @keys_to_copy
        |> Enum.reduce(%{}, fn key, result ->
          {key_from, key_to} =
            case key do
              {_, _} -> key
              key -> {key, key}
            end

          result
          |> Map.put(key_to, piped_response[key_from])
        end)
        # NOTE isShort is not shown on stream output. we will show results as type=video
        # NOTE duration is 0, not -1, for live streams
        |> Map.put("type", "stream")
        |> Map.put("url", "/watch?v=#{youtube_id}")
        |> Map.put(
          "uploaded",
          if String.contains?(raw_upload_date, "T") do
            raw_upload_date
            |> DateTime.from_iso8601()
            |> then(fn {:ok, dt, _tz} ->
              dt
              |> DateTime.to_unix(:millisecond)
            end)
          else
            # we usually don't get the real uploaded timestamp, so fill it with date at midnight
            raw_upload_date
            |> Date.from_iso8601!()
            |> DateTime.new!(~T[00:00:00])
            |> DateTime.to_unix(:millisecond)
          end
        )

      {:ok, %{results: [video_result], type: :video, title: video_result["title"], nextpage: nil}}
    end
  end

  defp resolve_youtube_entity({:playlist, playlist_id}) do
    fetch(%PlaylistSlot{youtube_id: playlist_id})
  end

  defp resolve_youtube_entity(err) do
    err
  end

  defp youtube_id_from_uri(host, url_path) do
    uri = URI.parse(url_path)

    cond do
      String.starts_with?(uri.path, "watch") ->
        if uri.query != nil do
          query =
            uri.query
            |> URI.decode_query()

          if query["v"] do
            {:ok, query["v"]}
          else
            Logger.error("invalid query params: #{inspect(query)}")
            {:input_error, :invalid_format}
          end
        else
          Logger.error("invalid /watch uri: #{inspect(uri)}")
          {:input_error, :invalid_format}
        end

      String.starts_with?(uri.path, "live") or
          String.starts_with?(uri.path, "shorts") ->
        uri.path
        |> String.split("/")
        |> Enum.at(1)
        |> then(fn maybe_youtube_id ->
          if maybe_youtube_id != nil do
            {:ok, maybe_youtube_id}
          else
            Logger.error("invalid live uri: #{inspect(uri)}")
            {:input_error, :invalid_format}
          end
        end)

      host in @host_by_path ->
        video_id = url_path |> String.split("?") |> Enum.at(0) |> String.split("/") |> Enum.at(0)
        {:ok, video_id}

      true ->
        Logger.error("invalid uri (for video parse): #{host} #{url_path}")
        {:input_error, :invalid_format}
    end
    |> then(fn
      {:ok, id} ->
        if String.length(id) == 11 do
          {:ok, id}
        else
          Logger.error("extracted id is not 11 characters. #{id}")
          {:input_error, :invalid_format}
        end

      v ->
        v
    end)
  end

  defp result_limit do
    max_pages =
      Application.get_env(:yt_search, YtSearch.Constants)[:pages_from_search] ||
        raise "invalid configuration"

    max_result_count =
      Application.get_env(:yt_search, YtSearch.Constants)[:results_from_search] ||
        raise("invalid configuration")

    %{
      max_pages: max_pages,
      max_result_count: max_result_count
    }
  end

  defp limit_config(entity) do
    page_key = ["pages_from_", entity] |> List.to_string() |> String.to_atom()
    max_pages = Application.get_env(:yt_search, YtSearch.Constants)[page_key]
    result_key = ["results_from_", entity] |> List.to_string() |> String.to_atom()
    max_result_count = Application.get_env(:yt_search, YtSearch.Constants)[result_key]
    search_config = result_limit()

    %{
      max_pages: max_pages || search_config[:max_pages],
      max_result_count: max_result_count || search_config[:max_result_count]
    }
  end

  defp channel_result_limit do
    limit_config("channels")
  end

  defp playlist_result_limit do
    limit_config("playlists")
  end

  defp trending_result_limit do
    limit_config("trending")
  end

  defp piped_search_call(tag, func, nextpage_func, id, result_list_extractor_fn, conf, opts) do
    do_piped_search_call(tag, func, nextpage_func, id, result_list_extractor_fn, conf, opts, %{})
  end

  defp do_piped_search_call(
         tag,
         func,
         nextpage_func,
         id,
         result_list_extractor_fn,
         conf,
         opts,
         state
       ) do
    current_results = state[:results] || []
    current_page = state[:current_page] || 0
    support_nextpage? = opts |> Keyword.get(:nextpage?, true)
    max_pages = conf.max_pages
    limit = conf.max_result_count

    cond do
      current_page >= max_pages ->
        {:ok,
         current_results
         |> Enum.take(limit)}

      Enum.count(current_results) >= limit ->
        Logger.debug("nextpage #{inspect(id)}: completed!")

        {:ok,
         state.results
         |> Enum.take(limit)}

      true ->
        given_page_results =
          if state[:nextpage] && support_nextpage? do
            Logger.debug("nextpage #{inspect(id)}: bumping to nextpage #{current_page}")

            piped_call(
              tag
              |> to_string
              |> then(fn x ->
                [x, "nextpage"]
                |> Enum.join("_")
              end)
              |> String.to_atom(),
              fn url, text ->
                nextpage_func.(url, text, state.nextpage)
              end,
              id,
              ignore_keys: ["nextpage"]
            )
          else
            Logger.debug("nextpage #{inspect(id)}: first call")
            piped_call(tag, func, id, ignore_keys: ["nextpage"])
          end

        case given_page_results do
          {:ok, results} ->
            result_list =
              results
              |> result_list_extractor_fn.()

            if Enum.empty?(result_list) do
              # no results? stop now.
              {:ok,
               current_results
               |> Enum.take(limit)}
            else
              new_state = %{
                results:
                  result_list
                  |> then(fn x -> Enum.concat(current_results, x) end),
                current_page: current_page + 1,
                nextpage:
                  case results do
                    v when is_list(v) -> nil
                    v when is_map(v) -> v["nextpage"]
                  end
              }

              if new_state.nextpage == nil do
                {:ok,
                 new_state.results
                 |> Enum.take(limit)}
              else
                do_piped_search_call(
                  tag,
                  func,
                  nextpage_func,
                  id,
                  result_list_extractor_fn,
                  conf,
                  opts,
                  new_state
                )
              end
            end

          # if it errors out, stop the flow entirely and return what we got
          v ->
            # TODO only apply degradation logic to text search
            # Logger.error(
            #  "Piped call to #{inspect(func)} failed, degrading list (to #{length(current_results)} entries): #{inspect(v)}"
            # )

            # current_results
            v
        end
    end
    |> then(fn
      {:ok, results} ->
        CallCounter.search_results(results)
        {:ok, results}

      v ->
        v
    end)
  end

  defp do_a_search(
         tag,
         func,
         id,
         result_list_extractor_fn,
         nextpage_extractor_fn,
         extra_fields_fn,
         conf
       ) do
    limit = conf.max_result_count

    with {:ok, results} <- piped_call(tag, func, id, ignore_keys: ["nextpage"]) do
      result_list =
        results
        |> result_list_extractor_fn.()
        |> Enum.take(limit)

      nextpage =
        results
        |> nextpage_extractor_fn.()
        |> then(fn
          # search results return nextpage as null string instead of null entity
          # channels and playlists return json entity tho
          # good code
          "null" -> nil
          v -> v
        end)

      {:ok,
       %{
         results: result_list,
         nextpage: nextpage
       }
       |> Map.merge(
         if extra_fields_fn != nil do
           extra_fields_fn.(results)
         else
           %{}
         end
       )}
    end
    |> then(fn
      {:ok, %{results: results}} = v ->
        CallCounter.search_results(results)
        v

      v ->
        v
    end)
  end

  defp piped_call(call_type, func, id, opts) do
    CallCounter.inc(call_type)

    start_ts = System.monotonic_time(:millisecond)
    result = func.(piped(), id)
    end_ts = System.monotonic_time(:millisecond)
    Latency.register(call_type, end_ts - start_ts)
    CallCounter.response(call_type, result)

    case result do
      {:ok, %{status: 200} = response} ->
        {:ok,
         response.body
         |> vrcjson_workaround(opts)}

      {:ok, %{status: 500, body: raw_body} = response} ->
        body =
          case raw_body
               |> then(fn body ->
                 case body do
                   {:ok, body} -> body |> Jason.decode()
                   v -> {:ok, v}
                 end
               end) do
            {:ok, body} ->
              body

            {:error, _} = val ->
              Logger.error(
                "an error happened while parsing 500, #{inspect(val)}, #{inspect(raw_body)}"
              )

              %{"message" => ""}
          end

        message = body["message"] || ""
        Logger.warning("piped errored with message: #{inspect(message)}")

        cond do
          String.contains?(message, "Video unavailable") ->
            Logger.warning("this is an unavailable youtube id")
            UnavailableVideoCounter.inc(:unavailable)
            {:error, :video_unavailable}

          String.contains?(
            message,
            "This video is no longer available because the YouTube account associated"
          ) ->
            Logger.warning("video dead because channel dead")
            UnavailableVideoCounter.inc(:dead_channel)
            {:error, :video_unavailable}

          String.contains?(message, "This channel does not exist") ->
            Logger.warning("this is a non existing channel")
            UnavailableVideoCounter.inc(:non_existent_channel)
            {:error, :channel_not_found}

          String.contains?(message, "This video is only available to Music Premium members") ->
            Logger.warning("This video is only available to Music Premium members")
            UnavailableVideoCounter.inc(:music_premium)
            {:error, :video_unavailable}

          String.contains?(message, "Premieres in") ->
            Logger.warning("it's a premiere! #{message}")
            UnavailableVideoCounter.inc(:future_premiere)
            {:error, :video_unavailable}

          String.contains?(message, "Premiere will begin shortly") ->
            Logger.warning("it's a premiere! #{message}")
            UnavailableVideoCounter.inc(:is_premiere)
            {:error, :video_unavailable}

          String.contains?(message, "This video is a paid video") ->
            UnavailableVideoCounter.inc(:paid)
            {:error, :video_unavailable}

          String.contains?(message, "This live event will begin in") ->
            Logger.warning("it's a premiere livestream! #{message}")
            UnavailableVideoCounter.inc(:future_premiere_livestream)
            {:error, :video_unavailable}

          String.contains?(message, "This live stream recording is not available") ->
            UnavailableVideoCounter.inc(:unavailable_livestream_recording)
            {:error, :video_unavailable}

          String.contains?(message, "This age-restricted video cannot be watched") ->
            Logger.warning("this video is age restricted!")
            UnavailableVideoCounter.inc(:age_restricted)
            {:error, :video_unavailable}

          String.contains?(message, "who has blocked it on copyright grounds") ->
            Logger.warning("this video is DMCA'd! #{message}")
            UnavailableVideoCounter.inc(:dmca)
            {:error, :video_unavailable}

          String.contains?(message, "Could not get any stream.") ->
            UnavailableVideoCounter.inc(:no_stream)
            {:error, :video_unavailable}

          String.contains?(message, "This video is private.") ->
            UnavailableVideoCounter.inc(:private_video)
            {:error, :video_unavailable}

          String.contains?(message, "geo restriction checker") ->
            UnavailableVideoCounter.inc(:geo_restriction_checker)
            {:error, :video_unavailable}

          String.contains?(message, "We're processing this video. Check back later.") ->
            UnavailableVideoCounter.inc(:in_processing)
            {:error, :video_unavailable}

          String.contains?(
            message,
            "This video has been removed for violating YouTube's policy on nudity or sexual content"
          ) ->
            UnavailableVideoCounter.inc(:nsfw)
            {:error, :video_unavailable}

          String.contains?(message, "This channel is not available") ->
            Logger.warning("this is an unavailable channel")
            {:error, :channel_unavailable}

          String.contains?(message, "Could not get channel name") ->
            {:error, :channel_unavailable}

          String.contains?(message, "Sign in to confirm") ->
            {:error, :blocked}

          true ->
            {:error, response}
        end

      {:ok, %Tesla.Env{} = response} ->
        {:error, response}

      {:error, _} = error_value ->
        error_value
    end
  end

  def trending(region \\ "US") do
    piped_search_call(
      :trending,
      &Piped.trending/2,
      nil,
      region,
      fn x -> x end,
      trending_result_limit(),
      nextpage?: false
    )
  end

  def extract_valid_streams(incoming_video_streams) do
    video_streams =
      incoming_video_streams
      |> Enum.map(fn stream ->
        # for some reason, piped does not expose width/height when videoOnly=true
        # extrapolate when that's the case

        if stream["height"] == 0 or stream["width"] == 0 do
          case stream["quality"] do
            "720p" ->
              stream
              |> Map.put("width", 1280)
              |> Map.put("height", 720)

            "360p" ->
              stream
              |> Map.put("width", 480)
              |> Map.put("height", 360)

            "480p" ->
              stream
              |> Map.put("width", 640)
              |> Map.put("height", 480)

            "240p" ->
              stream
              |> Map.put("width", 320)
              |> Map.put("height", 240)

            "144p" ->
              stream
              |> Map.put("width", 256)
              |> Map.put("height", 144)

            _ ->
              stream
          end
        else
          stream
        end
      end)

    # wanted format selection in ytdlp format:
    # mp4[height<=?1080][height>=?64][width>=?64]/best[height<=?1080][height>=?64][width>=?64]
    # we translate it into two Enum.filter calls, preffering first filter

    first_filter_results =
      video_streams
      |> Enum.filter(fn stream ->
        stream["mimeType"] == "video/mp4" and
          stream["height"] <= 1080 and
          stream["height"] >= 64 and
          stream["width"] >= 64 and
          not stream["videoOnly"]
      end)
      # order by pixel amount
      |> Enum.sort_by(fn stream -> stream["width"] * stream["height"] end, :desc)

    second_filter_results =
      video_streams
      |> Enum.filter(fn stream ->
        stream["height"] <= 1080 and
          stream["height"] >= 64 and
          stream["width"] >= 64 and
          not stream["videoOnly"]
      end)
      |> Enum.sort_by(fn stream -> stream["width"] * stream["height"] end, :desc)

    first_filter_results |> Enum.at(0) || second_filter_results |> Enum.at(0)
  end

  defp expiry_from_query(uri) do
    if uri.query == nil do
      nil
    else
      uri.query
      |> URI.decode_query()
      |> Map.get("expire")
      |> then(fn maybe_expiry ->
        if maybe_expiry == nil do
          nil
        else
          {value, ""} = Integer.parse(maybe_expiry)
          value
        end
      end)
    end
  end

  defp expiry_from_path(uri) do
    maybe_expiry_value =
      uri.path
      |> then(fn path ->
        if path == nil do
          ""
        else
          path
        end
      end)
      |> String.split("/")
      |> Enum.at(5)

    if maybe_expiry_value == nil do
      nil
    else
      case Integer.parse(maybe_expiry_value) do
        :error -> nil
        {expiry, _anything} -> expiry
      end
    end
  end

  def unproxied_piped_url(url) when is_bitstring(url) do
    url
    |> URI.parse()
    |> unproxied_piped_url
  end

  def unproxied_piped_url(%URI{} = uri) do
    query = (uri.query || "") |> URI.decode_query()
    host = query["host"] || uri.host

    uri
    |> Map.put(:host, host)
    |> Map.put(:authority, host)
    |> to_string
  end

  def expiry_from_uri(uri) do
    expiry_from_query(uri) || expiry_from_path(uri)
  end

  def extract_subtitles(meta) do
    subtitles = meta["subtitles"] || []

    result =
      subtitles
      |> Enum.map(fn subtitle ->
        if subtitle["autoGenerated"] do
          subtitle
        else
          # make it akin to ytdlp
          code = subtitle["code"]
          subtitle |> Map.put("code", "#{code}-orig")
        end
      end)
      # prefer english subtitles (we dont have subtitle selection features yet)
      |> Enum.filter(fn subtitle -> String.starts_with?(subtitle["code"], "en") end)
      |> Enum.map(fn subtitle ->
        # map all urls to direct calls, no need to use the piped proxy
        subtitle
        |> Map.put(
          "url",
          subtitle["url"] |> unproxied_piped_url
        )
      end)
      |> Enum.map(fn subtitle ->
        # map each to a task that fetches the subtitle from youtube
        Task.async(fn ->
          url = subtitle["url"]
          Logger.debug("subtitle, calling #{url}")

          case Tesla.get(url, opts: [adapter: [recv_timeout: 3000]]) do
            {:ok, %{status: 200} = response} ->
              {subtitle, response.body}

            result ->
              Logger.error("#{url} failed, got #{inspect(result)}")
              nil
          end
        end)
      end)
      |> Enum.map(fn task ->
        Task.await(task)
      end)
      |> Enum.filter(fn result -> result != nil end)

    if Enum.empty?(result) do
      {:error, :no_valid_subtitles_found}
    else
      {:ok, result}
    end
  end

  def extract_chapters(meta) do
    {:ok, meta["chapters"]}
  end

  def video_metadata(youtube_id) do
    case piped_call(:streams, &Piped.streams/2, youtube_id, nil) do
      {:error, :blocked} ->
        piped_call(:streams_retry, &Piped.streams/2, youtube_id, nil)

      v ->
        v
    end
  end

  defmodule Latency do
    use Prometheus.Metric

    def setup() do
      Histogram.declare(
        name: :yts_ytdlp_latency,
        help: "latency of certain yt-dlp calls",
        labels: [:call_type],
        buckets:
          [
            10..100//10,
            100..1000//100,
            1000..2000//100,
            2000..4000//500,
            4000..10000//1000,
            10000..20000//1500
          ]
          |> Enum.flat_map(&Enum.to_list/1)
          |> Enum.uniq()
      )
    end

    def register(call_type, latency) do
      Histogram.observe(
        [
          name: :yts_ytdlp_latency,
          labels: [call_type]
        ],
        latency
      )
    end
  end

  defp sponsorblock_call(call_type, func, id) do
    CallCounter.inc(call_type)

    start_ts = System.monotonic_time(:millisecond)
    result = func.(sponsorblock(), id)
    end_ts = System.monotonic_time(:millisecond)
    Latency.register(call_type, end_ts - start_ts)

    case result do
      {:ok, %{status: 200} = response} ->
        {:ok,
         response.body
         |> vrcjson_workaround}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %Tesla.Env{} = response} ->
        {:error, response}

      {:error, _} = error_value ->
        error_value
    end
  end

  def sponsorblock_segments(youtube_id) do
    sponsorblock_call(
      :sponsorblock_segments,
      &YtSearch.Sponsorblock.skip_segments/2,
      youtube_id
    )
  end
end
