defmodule YtSearch.Subtitle.CTAExtractor do
  @moduledoc """
  Detects YouTube engagement prompts (like, subscribe, bell notifications) 
  in WebVTT subtitle files and returns their timestamps.
  """
  require Logger

  # Common engagement patterns organized by type
  @engagement_patterns %{
    like: [
      ~r/like\s+this\s+video/i,
      ~r/like\s+the\s+video/i,
      ~r/give\s+it\s+a\s+like/i,
      ~r/smash\s+that\s+like/i,
      ~r/hit\s+the\s+like/i,
      ~r/don't\s+forget\s+to\s+like/i,
      ~r/please\s+like/i
    ],
    subscribe: [
      ~r/subscribe\s+for\s+more/i,
      ~r/subscribe\s+if\s+you\s+want/i,
      ~r/don't\s+forget\s+to\s+subscribe/i,
      ~r/make\s+sure\s+to\s+subscribe/i,
      ~r/please\s+subscribe/i,
      ~r/hit\s+subscribe/i
    ],
    like_and_subscribe: [
      ~r/like\s+and\s+subscribe/i,
      ~r/like\s+comment\s+subscribe/i,
      ~r/like\s+share\s+subscribe/i
    ],
    bell_notification: [
      ~r/hit\s+that\s+bell/i,
      ~r/ring\s+that\s+bell/i,
      ~r/smash\s+that\s+bell/i,
      ~r/notification\s+bell/i,
      ~r/turn\s+on\s+notifications/i
    ],
    general_cta: [
      ~r/support\s+the\s+channel/i,
      ~r/thanks\s+for\s+watching/i,
      ~r/see\s+you\s+in\s+the\s+next/i
    ]
  }

  def detect_engagement_prompts(vtt_content) when is_binary(vtt_content) do
    vtt_content
    |> limit_to_last_2kb()
    |> parse_vtt()
    |> find_engagement_patterns()
    |> Enum.sort_by(& &1.timestamp)
  end

  @max_bytes 2048
  defp limit_to_last_2kb(vtt_content) do
    content_size = byte_size(vtt_content)

    if content_size > @max_bytes do
      Logger.debug(
        "Limiting VTT content from #{content_size} bytes to last #{@max_bytes} bytes for performance"
      )

      # Take last 2KB but ensure we start from a complete subtitle block
      truncated = String.slice(vtt_content, -@max_bytes, @max_bytes)

      # Find the first complete subtitle block (starts after a double newline)
      case String.split(truncated, "\n\n", parts: 2) do
        [_incomplete_block, rest] -> rest
        [complete_content] -> complete_content
      end
    else
      vtt_content
    end
  end

  defp parse_vtt(vtt_content) do
    vtt_content
    |> String.split("\n\n")
    |> Enum.map(&parse_subtitle_block/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_subtitle_block(block) do
    lines = String.split(block, "\n", trim: true)

    case lines do
      [timestamp_line | text_lines] when length(text_lines) > 0 ->
        # Check if this looks like a timestamp line
        if String.contains?(timestamp_line, "-->") do
          # Clean timestamp line of alignment/position attributes
          clean_timestamp =
            timestamp_line
            |> String.split(" align:", parts: 2)
            |> List.first()
            |> String.trim()

          # Join all text lines and clean up
          text =
            text_lines
            |> Enum.join(" ")
            |> String.trim()
            |> clean_text()

          %{
            timestamp: clean_timestamp,
            text: text
          }
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp clean_text(text) do
    text
    # Remove HTML tags
    |> String.replace(~r/<[^>]*>/, "")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp find_engagement_patterns(subtitles) do
    subtitles
    |> Enum.flat_map(&check_subtitle_for_patterns/1)
  end

  defp check_subtitle_for_patterns(%{timestamp: timestamp, text: text}) do
    @engagement_patterns
    |> Enum.flat_map(fn {pattern_type, patterns} ->
      patterns
      |> Enum.filter(fn pattern ->
        Regex.match?(pattern, text)
      end)
      |> Enum.map(fn pattern ->
        # Extract the matched text for better context
        match = Regex.run(pattern, text, capture: :first) |> List.first()

        %{
          timestamp: timestamp,
          text: text,
          pattern: match,
          pattern_type: pattern_type
        }
      end)
    end)
  end

  @doc """
  Converts timestamp to seconds for easier processing.

  ## Example
      iex> YtSearch.Subtitle.CTAExtractor.timestamp_to_seconds("00:16:38.000")
      998.0
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

  ## Example
      iex> results = YtSearch.Subtitle.CTAExtractor.detect_engagement_prompts(vtt_content)
      iex> YtSearch.Subtitle.CTAExtractor.filter_by_type(results, :like)
      [%{pattern_type: :like, ...}]
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

  This groups prompts by pattern_type and merges any that have overlapping 
  or close timestamps within each type.

  ## Example
      iex> results = YtSearch.Subtitle.CTAExtractor.detect_engagement_prompts(vtt_content)
      iex> YtSearch.Subtitle.CTAExtractor.merge_overlapping_ranges(results)
      [%{timestamp: "00:16:38.000 --> 00:16:43.749", pattern_type: :like, ...}]
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

  ## Example
      iex> YtSearch.Subtitle.CTAExtractor.detect_and_merge_engagement_prompts(vtt_content)
      [%{timestamp: "00:16:38.000 --> 00:16:43.749", pattern_type: :like, ...}]
  """
  def detect_and_merge_engagement_prompts(vtt_content) do
    vtt_content
    |> detect_engagement_prompts()
    |> merge_overlapping_ranges()
  end
end
