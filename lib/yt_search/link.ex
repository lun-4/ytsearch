defmodule YtSearch.Mp4Link do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo

  @type t :: %__MODULE__{}

  @primary_key {:youtube_id, :string, autogenerate: false}

  schema "links" do
    field(:mp4_link, :string)
  end

  @spec fetch_by_id(String.t()) :: Mp4Link.t()
  def fetch_by_id(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s
    Repo.one(query)
  end

  @spec insert(String.t(), String.t()) :: Mp4Link.t()
  def insert(youtube_id, mp4_link) do
    %__MODULE__{youtube_id: youtube_id, mp4_link: mp4_link}
    |> Repo.insert!()
  end
end
