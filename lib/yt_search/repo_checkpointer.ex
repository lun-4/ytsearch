defmodule YtSearch.Repo.Checkpointer do
  @moduledoc """
  Flushes SQLite WAL files back into the main database files on shutdown.

  Started right after the repos in the supervision tree, so on shutdown it
  terminates after all workers have stopped (no more writes) but while the
  repo connections are still alive.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # trap exits so terminate/2 runs on supervisor shutdown
    Process.flag(:trap_exit, true)
    # repo list override for tests; defaults to all primaries
    {:ok, Keyword.get(opts, :repos)}
  end

  @impl true
  def terminate(_reason, repos) do
    Logger.info("checkpointing WALs for all primary repos...")

    (repos || YtSearch.Application.primaries())
    |> Enum.each(fn repo ->
      try do
        Logger.info("checkpointing #{inspect(repo)}")

        %{rows: [[busy, log_frames, checkpointed_frames]]} =
          repo.query!("PRAGMA wal_checkpoint(TRUNCATE);")

        if busy == 1 do
          Logger.warning(
            "#{inspect(repo)}: checkpoint busy, log=#{log_frames} checkpointed=#{checkpointed_frames}"
          )
        else
          Logger.info(
            "#{inspect(repo)}: checkpointed, log=#{log_frames} checkpointed=#{checkpointed_frames}"
          )
        end
      rescue
        exc ->
          Logger.error("#{inspect(repo)}: checkpoint failed: #{Exception.message(exc)}")
      end
    end)

    Logger.info("WAL checkpoint done!")
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      # 12 databases, each with busy_timeout of 5s; default 5s shutdown is too tight
      shutdown: 30_000
    }
  end
end
