defmodule YtSearch.Repo.Janitor do
  @moduledoc """
  Run incremental vacuums on the database
  """
  require Logger

  @page_count 20

  def tick() do
    YtSearch.Application.primaries()
    |> Enum.map(fn repo ->
      Logger.info("#{inspect(repo)} running vacuum at #{@page_count} pages")
      repo.query!("PRAGMA incremental_vacuum(#{@page_count});")
      Logger.info("#{inspect(repo)}: vacuum done")
    end)
  end
end
