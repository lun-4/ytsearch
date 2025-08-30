defmodule YtSearch.HlsManifest do
  @moduledoc """
  Module for generating HLS-like manifests for non-livestream YouTube videos.

  Creates a pseudo HLS manifest with separate video and audio streams,
  using the same stream selection logic as the regular video serving.
  """

  alias YtSearch.Youtube

  @doc """
  Generates an HLS manifest for a given video metadata.

  The manifest includes:
  - Master playlist with video and audio variants
  - Selected video stream based on quality (720p preferred)
  - Selected audio stream based on bitrate

  Returns {:ok, manifest_content} or {:error, reason}
  """
  def generate_manifest(video_metadata) when is_map(video_metadata) do
    if video_metadata["livestream"] do
      {:error, :is_livestream}
    else
      video_streams = video_metadata["videoStreams"] || []
      audio_streams = video_metadata["audioStreams"] || []

      with {:ok, selected_video} <- select_video_stream(video_streams),
           {:ok, selected_audio} <- select_audio_stream(audio_streams) do
        duration = video_metadata["duration"] || 0

        manifest_content = build_master_playlist(selected_video, selected_audio, duration)
        {:ok, manifest_content}
      else
        error -> error
      end
    end
  end

  @doc """
  Selects the best video stream using similar logic to Youtube.extract_valid_streams/1
  but adapted for manifest generation. Only uses 720p video-only streams - no fallback.
  """
  def select_video_stream(video_streams) when is_list(video_streams) do
    # Filter for 720p video-only MP4 streams only
    preferred_stream =
      video_streams
      |> Enum.filter(fn stream ->
        stream["videoOnly"] == true and
          stream["quality"] == "720p" and
          stream["mimeType"] == "video/mp4" and
          stream["height"] >= 64 and
          stream["width"] >= 64
      end)
      |> Enum.sort_by(fn stream -> stream["bitrate"] || 0 end, :desc)
      |> List.first()

    case preferred_stream do
      nil -> {:error, :no_suitable_video_stream}
      stream -> {:ok, stream}
    end
  end

  @doc """
  Selects the best audio stream, preferring higher bitrate MP4/AAC streams.
  """
  def select_audio_stream(audio_streams) when is_list(audio_streams) do
    # Prefer MP4/AAC streams, then WebM/Opus
    preferred_audio =
      audio_streams
      |> Enum.filter(fn stream ->
        # AAC-LC
        stream["mimeType"] == "audio/mp4" and
          stream["codec"] == "mp4a.40.2"
      end)
      |> Enum.sort_by(fn stream -> stream["bitrate"] || 0 end, :desc)
      |> List.first()

    fallback_audio =
      if preferred_audio == nil do
        audio_streams
        |> Enum.sort_by(fn stream -> stream["bitrate"] || 0 end, :desc)
        |> List.first()
      else
        preferred_audio
      end

    case fallback_audio do
      nil -> {:error, :no_suitable_audio_stream}
      stream -> {:ok, stream}
    end
  end

  @doc """
  Builds the master HLS playlist content using actual upstream YouTube URLs.
  """
  def build_master_playlist(video_stream, audio_stream, _duration) do
    video_bandwidth = video_stream["bitrate"] || 1_000_000
    audio_bandwidth = audio_stream["bitrate"] || 128_000
    combined_bandwidth = video_bandwidth + audio_bandwidth

    video_resolution = "#{video_stream["width"]}x#{video_stream["height"]}"
    video_codec = determine_video_codec(video_stream)
    audio_codec = determine_audio_codec(audio_stream)

    # Get the unproxied upstream URLs
    video_url = Youtube.unproxied_piped_url(video_stream["url"])
    audio_url = Youtube.unproxied_piped_url(audio_stream["url"])

    """
    #EXTM3U
    #EXT-X-VERSION:6

    # Audio-only variant
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Audio",DEFAULT=YES,AUTOSELECT=YES,URI="#{audio_url}"

    # Video variant with audio
    #EXT-X-STREAM-INF:BANDWIDTH=#{combined_bandwidth},RESOLUTION=#{video_resolution},CODECS="#{video_codec},#{audio_codec}",AUDIO="audio"
    #{video_url}
    """
  end

  @doc """
  Generates a video-only playlist for the selected video stream.
  """
  def build_video_playlist(video_stream, duration) do
    # For simplicity, treat the entire video as one segment
    # In a real HLS implementation, this would be split into segments
    video_url = Youtube.unproxied_piped_url(video_stream["url"])

    """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-TARGETDURATION:#{duration}
    #EXT-X-MEDIA-SEQUENCE:0
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXTINF:#{duration}.0,
    #{video_url}
    #EXT-X-ENDLIST
    """
  end

  @doc """
  Generates an audio-only playlist for the selected audio stream.
  """
  def build_audio_playlist(audio_stream, duration) do
    # For simplicity, treat the entire audio as one segment
    audio_url = Youtube.unproxied_piped_url(audio_stream["url"])

    """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-TARGETDURATION:#{duration}
    #EXT-X-MEDIA-SEQUENCE:0
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXTINF:#{duration}.0,
    #{audio_url}
    #EXT-X-ENDLIST
    """
  end

  # Helper functions for codec determination
  defp determine_video_codec(video_stream) do
    case video_stream["codec"] do
      "avc1." <> _ = codec -> codec
      "vp9" -> "vp09.00.10.08"
      "vp8" -> "vp08"
      # default H.264 baseline
      _ -> "avc1.42001e"
    end
  end

  defp determine_audio_codec(audio_stream) do
    case audio_stream["codec"] do
      # AAC-LC
      "mp4a.40.2" -> "mp4a.40.2"
      # HE-AAC
      "mp4a.40.5" -> "mp4a.40.5"
      "opus" -> "opus"
      # default AAC-LC
      _ -> "mp4a.40.2"
    end
  end
end
