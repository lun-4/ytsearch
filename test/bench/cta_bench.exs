# Benchmark script for CTA Extractor optimizations
#
# Run with: mix run test/bench/cta_bench.exs

# Load the test VTT file
small_vtt = File.read!("test/support/files/subtitle_with_ctas.vtt")

# Generate a larger VTT file by repeating the pattern
# This simulates a longer video with more subtitle blocks
generate_large_vtt = fn size_multiplier ->
  header = """
  WEBVTT
  Kind: captions
  Language: en

  """

  # Generate many subtitle blocks
  blocks =
    for i <- 0..(size_multiplier - 1) do
      # Create timestamps spaced throughout a long video
      start_seconds = i * 30
      end_seconds = start_seconds + 5

      hours = div(start_seconds, 3600)
      minutes = rem(div(start_seconds, 60), 60)
      seconds = rem(start_seconds, 60)

      end_hours = div(end_seconds, 3600)
      end_minutes = rem(div(end_seconds, 60), 60)
      end_seconds_rem = rem(end_seconds, 60)

      timestamp =
        "#{String.pad_leading(Integer.to_string(hours), 2, "0")}:" <>
          "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:" <>
          "#{String.pad_leading(Integer.to_string(seconds), 2, "0")}.000 --> " <>
          "#{String.pad_leading(Integer.to_string(end_hours), 2, "0")}:" <>
          "#{String.pad_leading(Integer.to_string(end_minutes), 2, "0")}:" <>
          "#{String.pad_leading(Integer.to_string(end_seconds_rem), 2, "0")}.000"

      # Mix of CTA and regular content
      text =
        case rem(i, 10) do
          0 -> "Please like and subscribe for more content!"
          1 -> "Don't forget to hit that bell!"
          2 -> "Thanks for watching!"
          3 -> "Make sure to subscribe if you want more tutorials."
          4 -> "Give it a like if you found this helpful."
          _ -> "This is some regular video content about programming and technology."
        end

      "#{timestamp}\n#{text}\n"
    end

  header <> Enum.join(blocks, "\n")
end

# Generate test data of different sizes
# ~50 blocks
medium_vtt = generate_large_vtt.(50)
# ~200 blocks
large_vtt = generate_large_vtt.(200)
# ~500 blocks
xlarge_vtt = generate_large_vtt.(500)

IO.puts("\n=== CTA Extractor Performance Benchmark ===\n")
IO.puts("Comparing old vs new implementation\n")
IO.puts("Small VTT:  #{byte_size(small_vtt)} bytes")
IO.puts("Medium VTT: #{byte_size(medium_vtt)} bytes")
IO.puts("Large VTT:  #{byte_size(large_vtt)} bytes")
IO.puts("XLarge VTT: #{byte_size(xlarge_vtt)} bytes")
IO.puts("")

# Check if HTTP service is running
IO.puts("Checking HTTP service...")
http_port = System.get_env("CTA_HTTP_PORT") || "8080"

case HTTPoison.get("http://localhost:#{http_port}/health") do
  {:ok, %HTTPoison.Response{status_code: 200}} ->
    IO.puts("✓ HTTP service ready on port #{http_port}")

  _ ->
    IO.puts("✗ HTTP service not running. Start with: cd cta5 && ./cta_http_server")
    System.halt(1)
end

# Verify both implementations produce the same results
IO.puts("Verifying correctness...")
old_result = YtSearch.Subtitle.CTAExtractor.detect_and_merge_engagement_prompts(small_vtt)
http_result = YtSearch.Subtitle.CTAExtractorHTTP.detect_and_merge_engagement_prompts(small_vtt)

# Sort all by timestamp for comparison
old_sorted = Enum.sort_by(old_result, & &1.timestamp)
http_sorted = Enum.sort_by(http_result, & &1.timestamp)

IO.puts("Old Elixir:  #{length(old_sorted)} CTAs")
IO.puts("HTTP:        #{length(http_sorted)} CTAs")

if length(old_sorted) == length(http_sorted) do
  IO.puts("✓ Both implementations found #{length(old_sorted)} CTAs")
else
  IO.puts("✗ MISMATCH in CTA counts!")
  IO.puts("  Old: #{length(old_sorted)}, HTTP: #{length(http_sorted)}")
  raise "mismatched implementation output"
end

IO.puts("")

# Run the benchmark
Benchee.run(
  %{
    "elixir" => fn input ->
      YtSearch.Subtitle.CTAExtractor.detect_and_merge_engagement_prompts(input)
    end,
    "http" => fn input ->
      YtSearch.Subtitle.CTAExtractorHTTP.detect_and_merge_engagement_prompts(input)
    end
  },
  inputs: %{
    "Small (2KB)" => small_vtt,
    "Medium (5KB)" => medium_vtt,
    "Large (20KB)" => large_vtt,
    "XLarge (50KB)" => xlarge_vtt
  },
  formatters: [
    Benchee.Formatters.Console
  ],
  time: 5,
  memory_time: 2,
  warmup: 2
)
