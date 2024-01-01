defmodule YtSearch.Repo.Analyzer do
  @moduledoc """
  Run ANALYZE on the database
  """
  require Logger

  def tick() do
    YtSearch.Application.primaries()
    |> Enum.map(fn repo ->
      Logger.info("#{inspect(repo)}: setting analysis_limit to 400")
      repo.query!("PRAGMA analysis_limit=400;")
      Logger.info("#{inspect(repo)}: running PRAGMA optimize on db")
      repo.query!("PRAGMA optimize;")
      Logger.info("#{inspect(repo)}: PRAGMA optimize: done!")
    end)
  end
end
