defmodule YtSearch.TrendingClient do
  @moduledoc """
  HTTP client for submitting video view events to trending server.
  Fire-and-forget - doesn't block main app.
  """
  require Logger

  @doc """
  Submit video view to trending server.
  Fire-and-forget - doesn't block main app.
  """
  def submit_view(%YtSearch.Slot{} = slot) do
    case System.get_env("EXTERNAL_TRENDING_NODE") do
      trending_url when is_binary(trending_url) and trending_url != "" ->
        Task.start(fn ->
          do_submit_view(trending_url, slot)
        end)

        :ok

      _ ->
        # Monolith mode: record directly if TrendingRepo is running locally
        if GenServer.whereis(YtSearch.Data.TrendingRepo) do
          Task.start(fn ->
            YtSearch.Trending.record_view(slot.youtube_id)
          end)
        end

        :ok
    end
  end

  defp do_submit_view(trending_url, slot) do
    try do
      payload = %{
        youtube_id: slot.youtube_id,
        slot_id: slot.id
      }

      url = "#{trending_url}/api/node/view"

      headers = [
        {"Authorization", "Bearer #{System.get_env("NODE_AUTH")}"},
        {"Content-Type", "application/json"}
      ]

      case HTTPoison.post(url, Jason.encode!(payload), headers, timeout: 5000) do
        {:ok, %{status_code: 200}} ->
          Logger.debug("Successfully submitted view for #{slot.youtube_id} to trending server")

        {:ok, %{status_code: status, body: body}} ->
          Logger.warning(
            "Trending server returned status #{status} for view #{slot.youtube_id}: #{body}"
          )

        {:error, reason} ->
          Logger.warning("Failed to submit view to trending server: #{inspect(reason)}")
      end
    rescue
      e ->
        Logger.error("Exception submitting view to trending server: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace())
    end
  end
end
