defmodule YtSearch.ThumbnailerClient do
  @moduledoc """
  HTTP client for syncing search slot data to thumbnailer node.
  Main app calls this module to keep thumbnailer state in sync.
  """
  require Logger

  alias YtSearch.{SearchSlot, Data}

  @doc """
  Submit thumbnail for download on thumbnailer node.
  Fire-and-forget - doesn't block main app.
  """
  def submit_thumbnail(youtube_id, thumbnail_url) do
    case System.get_env("EXTERNAL_THUMBNAIL_NODE") do
      nil ->
        :ok

      "" ->
        :ok

      thumbnailer_url ->
        Task.start(fn ->
          do_submit_thumbnail(thumbnailer_url, youtube_id, thumbnail_url)
        end)

        :ok
    end
  end

  @doc """
  Submit search slot to thumbnailer node for syncing.
  Fire-and-forget - doesn't block main app.
  """
  def submit_search_slot(search_slot) do
    case System.get_env("EXTERNAL_THUMBNAIL_NODE") do
      nil ->
        # No thumbnailer configured, skip
        :ok

      "" ->
        :ok

      thumbnailer_url ->
        # Fire and forget - don't block main app
        Task.start(fn ->
          do_submit(thumbnailer_url, search_slot)
        end)

        :ok
    end
  end

  defp do_submit_thumbnail(thumbnailer_url, youtube_id, thumbnail_url) do
    try do
      payload = %{
        youtube_id: youtube_id,
        thumbnail_url: thumbnail_url
      }

      url = "#{thumbnailer_url}/api/node/thumbnail"

      headers = [
        {"Authorization", "Bearer #{System.get_env("NODE_AUTH")}"},
        {"Content-Type", "application/json"}
      ]

      case HTTPoison.post(url, Jason.encode!(payload), headers, timeout: 5000) do
        {:ok, %{status_code: 200}} ->
          Logger.debug("Successfully submitted thumbnail #{youtube_id} to thumbnailer")

        {:ok, %{status_code: status, body: body}} ->
          Logger.warning(
            "Thumbnailer returned status #{status} for thumbnail #{youtube_id}: #{body}"
          )

        {:error, reason} ->
          Logger.warning("Failed to submit thumbnail to thumbnailer: #{inspect(reason)}")
      end
    rescue
      e ->
        Logger.error("Exception submitting thumbnail to thumbnailer: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
    end
  end

  defp do_submit(thumbnailer_url, search_slot) do
    try do
      # Gather all related slots
      video_slots = gather_video_slots(search_slot)
      channel_slots = gather_channel_slots(search_slot)

      # Build payload
      payload = %{
        search_slot_data: serialize_search_slot(search_slot),
        video_slots: Enum.map(video_slots, &serialize_slot/1),
        channel_slots: Enum.map(channel_slots, &serialize_channel_slot/1)
      }

      # POST to thumbnailer
      url = "#{thumbnailer_url}/api/node/search_slot"

      headers = [
        {"Authorization", "Bearer #{System.get_env("NODE_AUTH")}"},
        {"Content-Type", "application/json"}
      ]

      case HTTPoison.post(url, Jason.encode!(payload), headers, timeout: 5000) do
        {:ok, %{status_code: 200}} ->
          Logger.debug("Successfully synced search slot #{search_slot.id} to thumbnailer")

        {:ok, %{status_code: status, body: body}} ->
          Logger.warning(
            "Thumbnailer returned status #{status} for slot #{search_slot.id}: #{body}"
          )

        {:error, reason} ->
          Logger.warning("Failed to sync to thumbnailer: #{inspect(reason)}")
      end
    rescue
      e ->
        Logger.error("Exception syncing to thumbnailer: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
    end
  end

  defp gather_video_slots(search_slot) do
    # Parse slots_json and fetch all video slots
    search_slot
    |> SearchSlot.get_slots()
    |> Enum.filter(fn slot ->
      slot["type"] in ["video", "short", "livestream"]
    end)
    |> Enum.map(fn slot ->
      slot_id = String.to_integer(slot["slot_id"])
      Data.SlotRepo.get(YtSearch.Slot, slot_id)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp gather_channel_slots(search_slot) do
    # Parse slots_json and fetch all channel slots
    search_slot
    |> SearchSlot.get_slots()
    |> Enum.filter(fn slot ->
      Map.has_key?(slot, "channel_slot") and slot["channel_slot"] != nil
    end)
    |> Enum.map(fn slot ->
      channel_slot_id = String.to_integer(slot["channel_slot"])
      Data.ChannelSlotRepo.get(YtSearch.ChannelSlot, channel_slot_id)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp serialize_search_slot(search_slot) do
    Map.take(search_slot, [
      :id,
      :query,
      :slots_json,
      :type,
      :nextpage_data,
      :nextpage_data_hash,
      :nextpage_slot_id,
      :result_type,
      :result_title,
      :expires_at,
      :used_at,
      :keepalive,
      :inserted_at,
      :updated_at
    ])
    |> Enum.map(fn {k, v} -> {k, serialize_value(v)} end)
    |> Enum.into(%{})
  end

  defp serialize_slot(slot) do
    Map.take(slot, [
      :id,
      :youtube_id,
      :video_duration,
      :expires_at,
      :used_at,
      :keepalive,
      :type,
      :inserted_at,
      :updated_at
    ])
    |> Enum.map(fn {k, v} -> {k, serialize_value(v)} end)
    |> Enum.into(%{})
  end

  defp serialize_channel_slot(slot) do
    Map.take(slot, [
      :id,
      :youtube_id,
      :channel_name,
      :channel_url,
      :channel_verified,
      :expires_at,
      :used_at,
      :keepalive,
      :inserted_at,
      :updated_at
    ])
    |> Enum.map(fn {k, v} -> {k, serialize_value(v)} end)
    |> Enum.into(%{})
  end

  defp serialize_value(%NaiveDateTime{} = dt) do
    NaiveDateTime.to_iso8601(dt)
  end

  defp serialize_value(value), do: value
end
