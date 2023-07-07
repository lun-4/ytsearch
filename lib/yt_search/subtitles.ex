defmodule YtSearch.Subtitle do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo
  alias YtSearch.Youtube
  alias YtSearch.TTL

  @type t :: %__MODULE__{}

  # @primary_key {:youtube_id, :string, autogenerate: false}

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
    |> Repo.insert!()
  end
end
