defmodule YtSearch.Chapters do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo

  @type t :: %__MODULE__{}

  # 1h
  def ttl_seconds, do: 60 * 60

  @primary_key {:youtube_id, :string, autogenerate: false}

  schema "chapters" do
    field(:chapter_data, :string)
    timestamps()
  end

  @spec fetch(String.t()) :: t()
  def fetch(youtube_id) do
    Repo.replica().one(from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s)
  end

  # TODO fix typing
  @spec insert(String.t(), String.t()) :: t()
  def insert(youtube_id, chapter_data_nonstr) do
    chapter_data = chapter_data_nonstr |> Jason.encode!()

    %__MODULE__{youtube_id: youtube_id, chapter_data: chapter_data}
    |> Repo.insert!(
      on_conflict: [
        set: [
          chapter_data: chapter_data
        ]
      ]
    )
  end

  defmodule Cleaner do
    require Logger

    alias YtSearch.Repo
    alias YtSearch.Chapters

    import Ecto.Query

    def tick() do
      Logger.debug("cleaning chapters...")

      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-Chapters.ttl_seconds())

      {deleted_count, _entities} =
        from(s in Chapters,
          where:
            s.inserted_at <
              ^expiry_time
        )
        |> Repo.delete_all()

      Logger.info("deleted #{deleted_count} chapters")
    end
  end
end
