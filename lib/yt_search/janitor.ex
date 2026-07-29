defmodule YtSearch.Janitor do
  @moduledoc """
  Shared TTL sweep for the periodic janitors.

  Every janitor does the same dance: compute an expiry cutoff, read a bounded
  batch of expired rows from a janitor replica, chunk it, delete each chunk from
  the primary (re-checking expiry so rows refreshed after the replica snapshot
  survive), optionally remove the file backing each actually-deleted row, and
  throttle between full chunks.
  """

  require Logger
  import Ecto.Query
  alias YtSearch.SlotUtilities

  @doc """
  Deletes expired rows of a schema, returning how many were deleted.

  Options:
   - `:name` — human name used in the log lines ("subtitles")
   - `:schema` — Ecto schema module
   - `:repo` — primary repo, the one doing the deletes
   - `:replica` — janitor replica, the one selecting expiry candidates
   - `:keys` — identifying columns, usually the primary key
   - `:expiry_column` — column holding the timestamp (default `:inserted_at`)
   - `:ttl` — seconds, cutoff is `now - ttl` (default 0, for `expires_at` columns)
   - `:extra_where` — optional `Ecto.Query.dynamic` composed into both queries
   - `:select_limit` — how many candidates to pull per tick
   - `:chunk_size` — how many rows per delete statement
   - `:sleep_ms` — how long to sleep after a *full* chunk
   - `:file_path` — optional function receiving the key map of a deleted row,
     returning a path to `File.rm/1`
  """
  def sweep(opts) do
    name = Keyword.fetch!(opts, :name)
    schema = Keyword.fetch!(opts, :schema)
    repo = Keyword.fetch!(opts, :repo)
    replica = Keyword.fetch!(opts, :replica)
    keys = Keyword.fetch!(opts, :keys)
    expiry_column = Keyword.get(opts, :expiry_column, :inserted_at)
    ttl = Keyword.get(opts, :ttl, 0)
    extra_where = Keyword.get(opts, :extra_where)
    select_limit = Keyword.fetch!(opts, :select_limit)
    chunk_size = Keyword.fetch!(opts, :chunk_size)
    sleep_ms = Keyword.fetch!(opts, :sleep_ms)
    file_path = Keyword.get(opts, :file_path)

    Logger.info("cleaning #{name}...")

    cutoff = SlotUtilities.generate_unix_timestamp_integer() - ttl
    expired = expiry_predicate(expiry_column, cutoff, extra_where)

    deleted_count =
      from(s in schema, where: ^expired, limit: ^select_limit)
      |> select([s], map(s, ^keys))
      |> replica.all()
      |> Enum.chunk_every(chunk_size)
      |> Enum.map(fn chunk ->
        count = delete_chunk(chunk, schema, repo, keys, expired, file_path)

        # let other ops run for a while, but only when we're churning through full chunks
        if length(chunk) == chunk_size do
          :timer.sleep(sleep_ms)
        end

        count
      end)
      |> Enum.sum()

    Logger.info("deleted #{deleted_count} #{name}")
    deleted_count
  end

  defp delete_chunk(chunk, schema, repo, keys, expired, file_path) do
    query =
      chunk
      |> chunk_query(schema, keys, expired)
      |> then(fn query ->
        if file_path == nil do
          query
        else
          query |> select([s], map(s, ^keys))
        end
      end)

    {count, deleted} = repo.delete_all(query)

    if file_path != nil do
      # only remove files for rows we actually deleted
      (deleted || [])
      |> Enum.each(fn row -> File.rm(file_path.(row)) end)
    end

    count
  end

  # single key: a plain IN, which the primary key index can serve
  defp chunk_query(chunk, schema, [key], expired) do
    values = chunk |> Enum.map(&Map.fetch!(&1, key))
    chunk_match = dynamic([s], field(s, ^key) in ^values and ^expired)

    from(s in schema, where: ^chunk_match)
  end

  # composite key: match exactly the key tuples in this chunk. deleting by a
  # single column would wipe unexpired siblings (e.g. other subtitle languages)
  defp chunk_query(chunk, schema, keys, expired) do
    Enum.reduce(chunk, from(s in schema, where: false), fn row, query ->
      row_match =
        Enum.reduce(keys, expired, fn key, acc ->
          value = Map.fetch!(row, key)
          dynamic([s], ^acc and field(s, ^key) == ^value)
        end)

      or_where(query, ^row_match)
    end)
  end

  # NOTE: keep the unixepoch() fragment shape intact, the expression indexes
  # (e.g. thumbnails_v2_unixepoch_expires_at_index) match on it
  defp expiry_predicate(column, cutoff, nil) do
    dynamic([s], fragment("unixepoch(?)", field(s, ^column)) < ^cutoff)
  end

  defp expiry_predicate(column, cutoff, extra_where) do
    dynamic([s], ^expiry_predicate(column, cutoff, nil) and ^extra_where)
  end
end
