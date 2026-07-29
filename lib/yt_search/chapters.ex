defmodule YtSearch.Chapters do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Data.ChapterRepo

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
    alias YtSearch.Data.ChapterRepo
    alias YtSearch.Chapters

    def tick() do
      YtSearch.Janitor.sweep(
        name: "chapters",
        schema: Chapters,
        repo: ChapterRepo,
        replica: ChapterRepo.JanitorReplica,
        keys: [:youtube_id],
        expiry_column: :inserted_at,
        ttl: Chapters.ttl_seconds(),
        select_limit: 1000,
        chunk_size: 500,
        sleep_ms: 250
      )
    end
  end
end
