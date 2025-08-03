defmodule YtSearch.Youtube.Util do
  require Logger

  def to_watch_url(youtube_id) do
    "https://youtube.com/watch?v=#{youtube_id}"
  end

  def maybe_await(%Task{} = task, timeout \\ 5000) do
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        Logger.warning("task #{inspect(task)} failed with error: #{inspect(reason)}")
        nil

      nil ->
        Logger.warning("task #{inspect(task)} timeouted after #{timeout}ms")
        nil
    end
  end
end
