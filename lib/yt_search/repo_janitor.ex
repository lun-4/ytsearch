defmodule YtSearch.Repo.Janitor do
  @moduledoc """
  Run incremental vacuums on the database
  """
  require Logger

  @page_count 20

  def tick() do
    Logger.info("running vacuum at #{@page_count} pages for repos...")

    YtSearch.Application.primaries()
    |> Enum.map(fn repo ->
      repo.query!("PRAGMA incremental_vacuum(#{@page_count});")
    end)

    Logger.info("done!")
  end
end
