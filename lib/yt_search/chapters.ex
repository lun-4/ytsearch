defmodule YtSearch.Chapters do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Data.ChapterRepo
  alias YtSearch.Data.ChapterRepo.JanitorReplica

  @type t :: %__MODULE__{}

  # 1h
  def ttl_seconds, do: 60 * 60

  @primary_key {:youtube_id, :string, autogenerate: false}

  schema "chapters_v2" do
    field(:chapter_data, :string)
    timestamps()
  end

  @spec fetch(String.t()) :: t()
  def fetch(youtube_id) do
    ChapterRepo.replica(youtube_id).one(
      from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s
    )
  end

  # TODO fix typing
  @spec insert(String.t(), String.t()) :: t()
  def insert(youtube_id, chapter_data_nonstr) do
    chapter_data = chapter_data_nonstr |> Jason.encode!()

    %__MODULE__{youtube_id: youtube_id, chapter_data: chapter_data}
    |> ChapterRepo.insert!(
      on_conflict: [
        set: [
          chapter_data: chapter_data
        ]
      ]
    )
  end

  defmodule Cleaner do
    require Logger

    alias YtSearch.Data.ChapterRepo
    alias YtSearch.Data.ChapterRepo.JanitorReplica
    alias YtSearch.Chapters

    import Ecto.Query

    def tick() do
      Logger.debug("cleaning chapters...")

      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-Chapters.ttl_seconds())
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix()

      deleted_count =
        from(s in Chapters,
          where:
            fragment("unixepoch(?)", s.inserted_at) <
              ^expiry_time,
          limit: 1000
        )
        |> JanitorReplica.all()
        |> Enum.chunk_every(10)
        |> Enum.map(fn chunk ->
          chunk
          |> Enum.map(fn chapters ->
            ChapterRepo.delete(chapters)
            1
          end)
          |> then(fn count ->
            :timer.sleep(1500)
            count
          end)
          |> Enum.sum()
        end)
        |> Enum.sum()

      Logger.info("deleted #{deleted_count} chapters")
    end
  end
end
