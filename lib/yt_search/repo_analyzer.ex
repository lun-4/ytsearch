defmodule YtSearch.Repo.Analyzer do
  @moduledoc """
  Run ANALYZE on the database
  """
  require Logger
  alias YtSearch.Repo

  def tick() do
    Logger.info("setting analysis_limit to 400")
    Repo.query!("PRAGMA analysis_limit=400;")
    Logger.info("running PRAGMA optimize on db")
    Repo.query!("PRAGMA optimize;")
    Logger.info("PRAGMA optimize: done!")
  end
end
