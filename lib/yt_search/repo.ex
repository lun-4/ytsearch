defmodule YtSearch.Repo do
  use Ecto.Repo,
    otp_app: :yt_search,
    adapter: Ecto.Adapters.SQLite3,
    pool_size: 1,
    loggers: [YtSearch.Repo.Instrumenter, Ecto.LogEntry]

  defmodule Instrumenter do
    use Prometheus.EctoInstrumenter

    def label_value(:query, log_entry) do
      log_entry[:query]
    end
  end
end
