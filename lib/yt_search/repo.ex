defmodule YtSearch.Repo do
  defmodule Instrumenter do
    use Prometheus.EctoInstrumenter

    def label_value(:repo, log_entry) do
      log_entry[:repo] |> to_string
    end

    def label_value(:query, log_entry) do
      normalize_query(log_entry[:query])
    end

    @doc """
    Collapse dynamically-shaped SQL so each logical query maps to a single
    label value. Without this, every `IN (?,?,...)` arity and every length of
    the janitor's OR-chain deletes becomes its own permanent time series,
    ballooning /metrics to tens of megabytes.
    """
    def normalize_query(nil), do: ""

    def normalize_query(query) do
      query
      |> String.replace(~r/\(\?(?:,\?)+\)/, "(...)")
      |> String.split(" OR ")
      |> Enum.dedup()
      |> Enum.join(" OR ")
      |> truncate_label(400)
    end

    defp truncate_label(query, max) when byte_size(query) <= max, do: query
    defp truncate_label(query, max), do: binary_part(query, 0, max) <> "..."
  end
end
