defmodule YtSearchWeb.HelloController do
  use YtSearchWeb, :controller
  require Logger

  def hello(conn, _params) do
    trending_tab = fetch_trending_tab()

    conn
    |> json(%{online: true, trending_tab: trending_tab})
  end

  def fetch_trending_tab(v \\ nil) do
    case v || Cachex.get(:tabs, "trending") do
      {:ok, nil} ->
        if v != nil do
          raise "should not re-request on given do_fetch value"
        else
          fetch_trending_tab(do_fetch_trending_tab())
        end

      {:ok, :nothing} ->
        nil

      {:ok, data} ->
        data

      value ->
        Logger.error("trending tab fetch failed: #{inspect(value)}")
        nil
    end
  end

  defp do_fetch_trending_tab() do
    url = "https://www.youtube.com/feed/trending"

    Mutex.under(SearchMutex, url, fn ->
      case Cachex.get(:tabs, "trending") do
        {:ok, nil} ->
          {:ok, data} =
            url
            |> YtSearchWeb.SearchController.search_from_any_youtube_url()

          Cachex.put(
            :tabs,
            "trending",
            case data do
              nil -> :nothing
              v -> v
            end,
            ttl: 2 * 3600 * 1000
          )

          {:ok, data}

        v ->
          v
      end
    end)
  end

  defmodule Refresher do
    use GenServer
    require Logger

    alias YtSearch.Repo
    alias YtSearch.Subtitle

    import Ecto.Query

    def start_link(arg) do
      GenServer.start_link(__MODULE__, arg)
    end

    @impl true
    def init(_arg) do
      schedule_work()
      {:ok, %{}}
    end

    def handle_info(:work, state) do
      do_refresh()
      schedule_work()
      {:noreply, state}
    end

    def do_refresh() do
      Logger.info("refreshing trending tab slots...")

      case Cachex.get(:tabs, "trending") do
        {:ok, nil} ->
          nil

        {:ok, :nothing} ->
          nil

        {:ok, data} ->
          data["search_results"]
          |> Enum.each(fn search_result ->
            {slot_id, ""} = search_result["slot_id"] |> Integer.parse()

            case search_result["type"] do
              "video" ->
                slot = Slot.fetch_by_id(slot_id)
                # recreate it, effectively refreshing the slot id
                new_slot = Slot.create(slot.youtube_id, slot.video_duration)

                if new_slot.id != slot.id do
                  Logger.warning(
                    "trending tab refresher: new slot (#{new_slot.id}) created instead of (#{slot.id}), thumbnails will be broken"
                  )
                end

              _ ->
                nil
            end
          end)
      end

      Logger.info("trending tab refresher complete")
    end

    defp schedule_work() do
      # every 7 minutes, with a jitter of -2..2m
      next_tick =
        case Mix.env() do
          :prod -> 7 * 60 * 1000 + Enum.random((-2 * 60 * 1000)..(2 * 60 * 1000))
          _ -> 10000
        end

      Process.send_after(self(), :work, next_tick)
    end
  end
end
