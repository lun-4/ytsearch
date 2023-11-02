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

  @read_replicas [
    YtSearch.Repo.Replica1,
    YtSearch.Repo.Replica2,
    YtSearch.Repo.Replica3,
    YtSearch.Repo.Replica4,
    YtSearch.Repo.Replica5,
    YtSearch.Repo.Replica6,
    YtSearch.Repo.Replica7,
    YtSearch.Repo.Replica8
  ]

  # single purpose
  @dedicated_replicas [
    YtSearch.Repo.ThumbnailReplica
  ]

  def replica do
    Enum.random(@read_replicas)
  end

  for repo <- @read_replicas ++ @dedicated_replicas do
    default_dynamic_repo =
      if Mix.env() == :test do
        YtSearch.Repo
      else
        repo
      end

    defmodule repo do
      use Ecto.Repo,
        otp_app: :yt_search,
        adapter: Ecto.Adapters.SQLite3,
        pool_size: 1,
        loggers: [YtSearch.Repo.Instrumenter, Ecto.LogEntry],
        read_only: true,
        default_dynamic_repo: default_dynamic_repo
    end
  end

  defmodule Instrumenter do
    use Prometheus.EctoInstrumenter

    def label_value(:query, log_entry) do
      log_entry[:query]
    end
  end
end
