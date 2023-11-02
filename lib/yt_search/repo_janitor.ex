defmodule YtSearch.Repo.Janitor do
  @moduledoc """
  Run incremental vacuums on the database
  """
  require Logger
  alias YtSearch.Repo

  @page_count 500

  def tick() do
    Logger.info("running vacuum at #{@page_count} pages")
    Repo.query!("PRAGMA incremental_vacuum(#{@page_count});")
    Logger.info("vacuum done")
  end
end
