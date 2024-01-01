defmodule YtSearch.Repo.FreelistMeter do
  require Logger

  defmodule Gauge do
    use Prometheus.Metric

    def setup() do
      Gauge.declare(
        name: :yts_freelist_count,
        help: "amount of db pages that are in the freelist",
        labels: [:repo]
      )
    end

    def set(repo, value) do
      Gauge.set([name: :yts_freelist_count, labels: [repo]], value)
    end
  end

  def tick() do
    Logger.debug("calculating freelist count...")

    YtSearch.Application.primaries()
    |> Enum.map(fn repo ->
      %{rows: [[freelist_count]]} = repo.query!("PRAGMA freelist_count;")
      __MODULE__.Gauge.set(repo, freelist_count)
      freelist_count
    end)
    |> Enum.reduce(fn x, acc -> x + acc end)
  end
end
