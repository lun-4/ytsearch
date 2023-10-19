defmodule YtSearch.Repo do
  use Ecto.Repo,
    otp_app: :yt_search,
    adapter: Ecto.Adapters.SQLite3,
    pool_size: 20,
    loggers: [YtSearch.Repo.Instrumenter, Ecto.LogEntry]

  def janitor_repo_id do
    if Mix.env() == :test do
      # required due to SQL sandbox
      __MODULE__
    else
      :janitor_repo
    end
  end

  defmodule Instrumenter do
    use Prometheus.EctoInstrumenter

    def label_value(:query, log_entry) do
      log_entry[:query]
    end
  end
end
