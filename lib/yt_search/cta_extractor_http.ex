defmodule YtSearch.Subtitle.CTAExtractorHTTP do
  @moduledoc """
  Detects YouTube engagement prompts using an HTTP service for performance.

  This module calls a Go HTTP service that performs CTA extraction.
  The service should be running on the configured host/port.
  """

  @doc """
  Detects engagement prompts by calling the HTTP service.
  """
  def detect_engagement_prompts(vtt_content) when is_binary(vtt_content) do
    url = get_service_url()

    case HTTPoison.post(url, vtt_content, [{"Content-Type", "text/plain"}], recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, results} when is_list(results) ->
            # Convert string keys to atoms to match the Elixir interface
            results
            |> Enum.map(fn result ->
              %{
                timestamp: result["timestamp"],
                text: result["text"],
                pattern: result["pattern"],
                pattern_type: String.to_atom(result["pattern_type"])
              }
            end)
            |> Enum.sort_by(& &1.timestamp)

          _ ->
            []
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        require Logger
        Logger.error("CTA HTTP service returned status #{status}")
        []

      {:error, %HTTPoison.Error{reason: reason}} ->
        require Logger
        Logger.error("CTA HTTP service request failed: #{inspect(reason)}")
        []
    end
  rescue
    error ->
      require Logger
      Logger.error("CTA HTTP service error: #{inspect(error)}")
      []
  end

  @doc """
  Converts timestamp to seconds for easier processing.
  """
  def timestamp_to_seconds(timestamp) when is_binary(timestamp) do
    # Handle timestamp ranges by taking the start time
    start_time =
      timestamp
      |> String.split(" --> ")
      |> List.first()

    case String.split(start_time, ":") do
      [hours, minutes, seconds] ->
        {h, _} = Integer.parse(hours)
        {m, _} = Integer.parse(minutes)
        {s, _} = Float.parse(seconds)

        h * 3600 + m * 60 + s

      [minutes, seconds] ->
        {m, _} = Integer.parse(minutes)
        {s, _} = Float.parse(seconds)

        m * 60 + s

      _ ->
        0.0
    end
  end

  @doc """
  Filters results by pattern type.
  """
  def filter_by_type(results, pattern_type) do
    Enum.filter(results, &(&1.pattern_type == pattern_type))
  end

  @doc """
  Gets a summary of all detected engagement prompts.
  """
  def get_summary(results) do
    results
    |> Enum.group_by(& &1.pattern_type)
    |> Enum.map(fn {type, items} ->
      {type, length(items)}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Merges overlapping or consecutive engagement prompts by pattern type and timestamp.
  """
  def merge_overlapping_ranges(results) do
    results
    |> Enum.group_by(& &1.pattern_type)
    |> Enum.flat_map(fn {_pattern_type, type_results} ->
      merge_type_group(type_results)
    end)
    |> Enum.sort_by(&timestamp_to_seconds(&1.timestamp))
  end

  defp merge_type_group(type_results) do
    type_results
    |> Enum.sort_by(&timestamp_to_seconds(&1.timestamp))
    |> merge_consecutive_ranges([])
  end

  defp merge_consecutive_ranges([], acc), do: Enum.reverse(acc)

  defp merge_consecutive_ranges([current | rest], []) do
    merge_consecutive_ranges(rest, [current])
  end

  defp merge_consecutive_ranges([current | rest], [last_merged | acc_tail] = acc) do
    if ranges_should_merge?(last_merged, current) do
      merged = merge_two_ranges(last_merged, current)
      merge_consecutive_ranges(rest, [merged | acc_tail])
    else
      merge_consecutive_ranges(rest, [current | acc])
    end
  end

  defp ranges_should_merge?(range1, range2) do
    # Check if ranges overlap or are very close (within 2 seconds)
    {_, end1} = parse_timestamp_range(range1.timestamp)
    {start2, _} = parse_timestamp_range(range2.timestamp)

    # Ranges overlap if start2 <= end1 + 2 seconds (allowing small gaps)
    start2 <= end1 + 2.0
  end

  defp merge_two_ranges(range1, range2) do
    {start1, end1} = parse_timestamp_range(range1.timestamp)
    {start2, end2} = parse_timestamp_range(range2.timestamp)

    # Use the earliest start and latest end
    merged_start = min(start1, start2)
    merged_end = max(end1, end2)

    # Use the longer text for better context
    merged_text =
      if String.length(range1.text) >= String.length(range2.text) do
        range1.text
      else
        range2.text
      end

    # Combine patterns for better context
    patterns = [range1.pattern, range2.pattern] |> Enum.uniq() |> Enum.join(", ")

    %{
      timestamp: format_timestamp_range(merged_start, merged_end),
      text: merged_text,
      pattern: patterns,
      pattern_type: range1.pattern_type
    }
  end

  defp parse_timestamp_range(timestamp_string) do
    [start_str, end_str] = String.split(timestamp_string, " --> ")
    {timestamp_to_seconds(start_str), timestamp_to_seconds(end_str)}
  end

  defp format_timestamp_range(start_seconds, end_seconds) do
    "#{seconds_to_timestamp(start_seconds)} --> #{seconds_to_timestamp(end_seconds)}"
  end

  defp seconds_to_timestamp(seconds) do
    hours = trunc(seconds / 3600)
    remaining_seconds = seconds - hours * 3600
    minutes = trunc(remaining_seconds / 60)
    secs = remaining_seconds - minutes * 60

    # Format with milliseconds
    milliseconds = trunc((secs - trunc(secs)) * 1000)
    secs_int = trunc(secs)

    "#{String.pad_leading(Integer.to_string(hours), 2, "0")}:#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(secs_int), 2, "0")}.#{String.pad_leading(Integer.to_string(milliseconds), 3, "0")}"
  end

  @doc """
  Convenience function that detects engagement prompts and automatically merges overlapping ranges.
  """
  def detect_and_merge_engagement_prompts(vtt_content) do
    vtt_content
    |> detect_engagement_prompts()
    |> merge_overlapping_ranges()
  end

  # Get the service URL from environment variable or use default
  defp get_service_url do
    host = System.get_env("CTA_HTTP_HOST") || "localhost"
    port = System.get_env("CTA_HTTP_PORT") || "8080"
    "http://#{host}:#{port}/detect"
  end
end
