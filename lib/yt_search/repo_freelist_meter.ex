defmodule YtSearch.Repo.FreelistMeter do
  require Logger
  alias YtSearch.Repo

  defmodule Gauge do
    use Prometheus.Metric

    def setup() do
      Gauge.declare(
        name: :yts_freelist_count,
        help: "amount of db pages that are in the freelist",
        labels: []
      )
    end

    def set(value) do
      Gauge.set([name: :yts_freelist_count, labels: []], value)
    end
  end

  def tick() do
    Logger.debug("calculating freelist count...")
    %{rows: [[freelist_count]]} = Repo.query!("PRAGMA freelist_count;")
    __MODULE__.Gauge.set(freelist_count)
    freelist_count
  end
end
