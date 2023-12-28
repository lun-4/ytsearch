defmodule YtSearch.Sponsorblock.Segments do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo

  @type t :: %__MODULE__{}

  # 15 min
  def ttl_seconds, do: 15 * 60

  @primary_key {:youtube_id, :string, autogenerate: false}

  schema "sponsorblock_segments" do
    field(:segments_json, :string)
    timestamps()
  end

  @spec fetch(String.t()) :: t()
  def fetch(youtube_id) do
    Repo.replica(youtube_id).one(
      from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s
    )
  end

  @spec insert(String.t(), String.t()) :: t()
  def insert(youtube_id, segments_json_str) do
    segments_json = segments_json_str |> Jason.encode!()

    %__MODULE__{youtube_id: youtube_id, segments_json: segments_json}
    |> Repo.insert!(
      on_conflict: [
        set: [
          segments_json: segments_json
        ]
      ]
    )
  end

  defmodule Cleaner do
    require Logger

    alias YtSearch.Repo
    alias YtSearch.Sponsorblock.Segments

    import Ecto.Query

    def tick() do
      Logger.debug("cleaning segments...")

      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-Segments.ttl_seconds())

      {deleted_count, _entities} =
        from(s in Segments,
          where:
            s.inserted_at <
              ^expiry_time
        )
        |> Repo.delete_all()

      Logger.info("deleted #{deleted_count} segments")
    end
  end
end
