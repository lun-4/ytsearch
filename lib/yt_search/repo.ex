defmodule YtSearch.Repo do
  use Ecto.Repo,
    otp_app: :yt_search,
    adapter: Ecto.Adapters.SQLite3,

    # sqlite does not do multi-writer. pool_size is effectively one,
    # if it's larger than one, then Database Busy errors haunt you
    # the trick to make concurrency happen is to create "read replicas"
    # that are effectively a pool of readers. this works because we're in WAL mode
    pool_size: 1,
    loggers: [YtSearch.Repo.Instrumenter, Ecto.LogEntry]

  @replicas [
    YtSearch.Repo.Replica1,
    YtSearch.Repo.Replica2,
    YtSearch.Repo.Replica3,
    YtSearch.Repo.Replica4
  ]

  def replica do
    Enum.random(@replicas)
  end

  for repo <- @replicas do
    defmodule repo do
      use Ecto.Repo,
        otp_app: :yt_search,
        adapter: Ecto.Adapters.SQLite3,
        pool_size: 1,
        loggers: [YtSearch.Repo.Instrumenter, Ecto.LogEntry],
        read_only: true
    end
  end

  defmodule Instrumenter do
    use Prometheus.EctoInstrumenter

    def label_value(:query, log_entry) do
      log_entry[:query]
    end
  end
end
