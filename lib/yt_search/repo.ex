defmodule YtSearch.Repo do
  defmodule Instrumenter do
    use Prometheus.EctoInstrumenter

    def label_value(:repo, log_entry) do
      log_entry[:repo]
    end

    def label_value(:query, log_entry) do
      log_entry[:query]
    end
  end
end
