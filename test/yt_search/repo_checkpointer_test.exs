defmodule YtSearch.Repo.CheckpointerTest do
  use ExUnit.Case, async: false

  # real, non-sandboxed repo so the checkpoint actually runs against a WAL file
  defmodule ScratchRepo do
    use Ecto.Repo, otp_app: :yt_search, adapter: Ecto.Adapters.SQLite3
  end

  test "truncates the WAL file on supervisor shutdown" do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "yts_checkpointer_test_#{System.unique_integer([:positive])}.db"
      )

    on_exit(fn ->
      Path.wildcard(db_path <> "*") |> Enum.each(&File.rm/1)
    end)

    start_supervised!({ScratchRepo, database: db_path, journal_mode: :wal, pool_size: 1})

    ScratchRepo.query!("CREATE TABLE things (id INTEGER PRIMARY KEY, data TEXT) STRICT;")

    for i <- 1..50 do
      ScratchRepo.query!("INSERT INTO things (data) VALUES (?);", ["thing #{i}"])
    end

    wal_path = db_path <> "-wal"
    assert File.stat!(wal_path).size > 0

    start_supervised!({YtSearch.Repo.Checkpointer, repos: [ScratchRepo]})
    :ok = stop_supervised(YtSearch.Repo.Checkpointer)

    assert File.stat!(wal_path).size == 0
  end
end
