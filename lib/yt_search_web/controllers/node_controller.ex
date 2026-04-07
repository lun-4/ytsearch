defmodule YtSearchWeb.NodeController do
  @moduledoc """
  Node API for receiving search slot syncs from main app.
  Used by thumbnailer node to receive authoritative state updates.
  """
  use YtSearchWeb, :controller
  require Logger

  alias YtSearch.{SearchSlot, Slot, ChannelSlot}
  alias YtSearch.Data.{SlotRepo, SearchSlotRepo, ChannelSlotRepo}

  plug(:authenticate_node)

  defp authenticate_node(conn, _opts) do
    expected_token = System.get_env("NODE_AUTH")

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token == expected_token ->
        conn

      _ ->
        conn
        |> put_status(401)
        |> json(%{error: "unauthorized"})
        |> halt()
    end
  end

  def submit_thumbnail(conn, params) do
    youtube_id = params["youtube_id"]
    thumbnail_url = params["thumbnail_url"]
    keepalive = params["keepalive"] || false

    if youtube_id == nil or thumbnail_url == nil do
      conn
      |> put_status(400)
      |> json(%{error: "missing youtube_id or thumbnail_url"})
    else
      # Trigger background download (same as main app)
      opts = if keepalive, do: [keepalive: true], else: []

      Task.Supervisor.async_nolink(YtSearch.ThumbnailSupervisor, fn ->
        :ets.insert(:thumbnail_tasks, {youtube_id, self()})

        try do
          unproxied_url = YtSearch.Youtube.unproxied_piped_url(thumbnail_url)

          YtSearch.Youtube.Thumbnail.maybe_download_thumbnail(
            youtube_id,
            unproxied_url,
            opts
          )
        after
          :ets.delete(:thumbnail_tasks, youtube_id)
        end
      end)

      json(conn, %{status: "ok"})
    end
  end

  def unkeepalive_thumbnails(conn, params) do
    youtube_ids = params["youtube_ids"] || []

    # Unkeepalive all specified thumbnails
    import Ecto.Query

    youtube_ids
    |> Enum.each(fn youtube_id ->
      from(t in YtSearch.Thumbnail,
        update: [set: [keepalive: false]],
        where: t.id == ^youtube_id
      )
      |> YtSearch.Data.ThumbnailRepo.update_all([])
    end)

    json(conn, %{status: "ok", count: length(youtube_ids)})
  end

  def submit_view(conn, params) do
    youtube_id = params["youtube_id"]

    if youtube_id == nil do
      conn
      |> put_status(400)
      |> json(%{error: "missing youtube_id"})
    else
      YtSearch.Data.TrendingRepo.transaction(
        fn ->
          YtSearch.Data.TrendingRepo.query!("""
            INSERT INTO video_counter (yt_video_id, view_count)
            VALUES (?, 1)
            ON CONFLICT(yt_video_id) DO UPDATE SET
              view_count = view_count + 1
          """, [youtube_id])

          YtSearch.Data.TrendingRepo.query!("""
            INSERT INTO video_views (yt_video_id, viewed_at)
            VALUES (?, datetime('now'))
          """, [youtube_id])
        end,
        mode: :immediate
      )

      json(conn, %{status: "ok"})
    end
  end

  def submit_search_slot(conn, params) do
    # Extract data from params
    search_slot_data = params["search_slot_data"]
    video_slots = params["video_slots"] || []
    channel_slots = params["channel_slots"] || []

    # NOTE: cant do cross-db transactions
    # we'll just be optimistic and assert everything syncs up right
    Enum.each(video_slots, &upsert_slot!/1)
    Enum.each(channel_slots, &upsert_channel_slot!/1)
    upsert_search_slot!(search_slot_data)

    json(conn, %{status: "ok"})
  end

  defp upsert_slot!(slot_data) do
    import Ecto.Query

    # Convert string keys to atoms for struct
    slot_attrs =
      slot_data
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Enum.into(%{})

    # Parse datetime fields
    slot_attrs =
      slot_attrs
      |> Map.update(:expires_at, nil, &parse_datetime/1)
      |> Map.update(:used_at, nil, &parse_datetime/1)
      |> Map.update(:inserted_at, nil, &parse_datetime/1)
      |> Map.update(:updated_at, nil, &parse_datetime/1)

    SlotRepo.transaction(
      fn ->
        # Delete any existing slot with same id OR youtube_id
        from(s in Slot,
          where: s.id == ^slot_attrs.id or s.youtube_id == ^slot_attrs.youtube_id
        )
        |> SlotRepo.delete_all()

        SlotRepo.insert!(struct(Slot, slot_attrs))
      end,
      mode: :immediate
    )
  end

  defp upsert_channel_slot!(slot_data) do
    import Ecto.Query

    slot_attrs =
      slot_data
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Enum.into(%{})

    slot_attrs =
      slot_attrs
      |> Map.update(:expires_at, nil, &parse_datetime/1)
      |> Map.update(:used_at, nil, &parse_datetime/1)
      |> Map.update(:inserted_at, nil, &parse_datetime/1)
      |> Map.update(:updated_at, nil, &parse_datetime/1)

    ChannelSlotRepo.transaction(
      fn ->
        # Delete any existing slot with same id OR youtube_id
        from(s in ChannelSlot,
          where: s.id == ^slot_attrs.id or s.youtube_id == ^slot_attrs.youtube_id
        )
        |> ChannelSlotRepo.delete_all()

        ChannelSlotRepo.insert!(struct(ChannelSlot, slot_attrs))
      end,
      mode: :immediate
    )
  end

  defp upsert_search_slot!(search_slot_data) do
    import Ecto.Query

    slot_attrs =
      search_slot_data
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Enum.into(%{})

    slot_attrs =
      slot_attrs
      |> Map.update(:expires_at, nil, &parse_datetime/1)
      |> Map.update(:used_at, nil, &parse_datetime/1)
      |> Map.update(:inserted_at, nil, &parse_datetime/1)
      |> Map.update(:updated_at, nil, &parse_datetime/1)
      |> Map.update(:type, nil, &parse_atom/1)
      |> Map.update(:result_type, nil, &parse_atom/1)

    SearchSlotRepo.transaction(
      fn ->
        # Delete any existing slot with same id OR query
        from(s in SearchSlot,
          where: s.id == ^slot_attrs.id or s.query == ^slot_attrs.query
        )
        |> SearchSlotRepo.delete_all()

        SearchSlotRepo.insert!(struct(SearchSlot, slot_attrs))
      end,
      mode: :immediate
    )
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(%NaiveDateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case NaiveDateTime.from_iso8601(str) do
      {:ok, dt} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_atom(nil), do: nil
  defp parse_atom(atom) when is_atom(atom), do: atom

  defp parse_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  end
end
