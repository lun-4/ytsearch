defmodule YtSearch.PipedBenchmarking do
  alias YtSearch.Piped
  require Logger

  defp piped_call(func, host, arg0) do
    Logger.debug("calling #{inspect(func)}, #{inspect(arg0)}")
    start_ts = System.monotonic_time(:millisecond)
    {:ok, %{status: 200} = _} = func.(host, arg0)
    end_ts = System.monotonic_time(:millisecond)
    end_ts - start_ts
  end

  @video_ids [
    "5tsAoSqRr_k",
    "4tVvCEQW5Sc",
    "ukg5HMS-kfU",
    "KYdKKQBvNqo",
    "SKrUw_gL054",
    "20vPbH6UWIc",
    "2aeaTlwC27g",
    "1ba93qFdaP8",
    "qQu7cnPHAZM",
    "FmLyJYmvlog"
  ]

  @videos_with_subtitles [
    "X3byz3txpso",
    "7H4eg2jOvVw",
    "7uUc_DBzC3g",
    "uBOVHaFWX5w",
    "RTA3Ls-WAcw",
    "H-YaJOif77E"
  ]

  defp run_streams_for_ids(ids, host) do
    ids
    |> Enum.map(fn youtube_id ->
      Task.async(fn ->
        piped_call(&Piped.streams/2, host, youtube_id)
      end)
    end)
    |> Enum.map(&Task.await/1)
  end

  def run do
    [host] = System.argv()
    Logger.debug("host: #{host}")

    latencies =
      1..5
      |> Enum.map(fn _ ->
        @video_ids
        |> Enum.concat(@videos_with_subtitles)
        |> run_streams_for_ids(host)
      end)
      # turn [x, y, z] + [a, b, c]
      # into [[x, a], [y, b], [c, z]]
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn latencies ->
        %{
          max: Enum.max(latencies),
          min: Enum.min(latencies),
          avg: Enum.sum(latencies) / Enum.count(latencies)
        }
      end)

    summary =
      latencies
      |> Enum.reduce(%{max: 0, min: 0, avg: 0}, fn full_entry, result ->
        %{
          max: max(result[:max], full_entry[:max]),
          min: max(result[:min], full_entry[:min]),
          avg: max(result[:avg], full_entry[:avg])
        }
      end)

    IO.puts("streams")
    IO.inspect(latencies)
    IO.puts("streams summary")
    IO.inspect(summary)

    latencies =
      @videos_with_subtitles
      |> Enum.map(fn youtube_id ->
        piped_call(&Piped.streams/2, host, youtube_id)
      end)

    IO.puts("streams w/ subtitles (TODO fetch underlying sub)")
    IO.inspect(latencies)
  end
end

YtSearch.PipedBenchmarking.run()
