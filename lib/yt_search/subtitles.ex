defmodule YtSearch.Subtitle do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo

  @type t :: %__MODULE__{}

  # 12 hours ttl
  def ttl_seconds, do: 12 * 60 * 60

  @primary_key false

  schema "subtitles" do
    field(:youtube_id, :string, primary_key: true, autogenerate: false)
    field(:language, :string, primary_key: true)
    field(:subtitle_data, :string)
    timestamps()
  end

  @spec fetch(String.t()) :: [Subtitle.t()]
  def fetch(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s
    Repo.all(query)
  end

  @spec insert(String.t(), String.t(), String.t() | nil) :: Subtitle.t()
  def insert(youtube_id, language, subtitle_data) do
    %__MODULE__{youtube_id: youtube_id, language: language, subtitle_data: subtitle_data}
    |> Repo.insert!(
      on_conflict: [
        set: [
          subtitle_data: subtitle_data
        ]
      ]
    )
  end

  defmodule Cleaner do
    require Logger

    alias YtSearch.Repo
    alias YtSearch.Subtitle

    import Ecto.Query

    def tick() do
      Logger.info("cleaning subtitles...")

      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-Subtitle.ttl_seconds())
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix()

      deleted_count =
        from(s in Subtitle,
          where:
            fragment("unixepoch(?)", s.inserted_at) <
              ^expiry_time,
          limit: 5000
        )
        |> Repo.all()
        |> Enum.map(fn subtitle ->
          IO.inspect(subtitle)
          Repo.delete(subtitle)
          1
        end)
        |> Enum.sum()

      Logger.info("deleted #{deleted_count} subtitles")
    end
  end
end
