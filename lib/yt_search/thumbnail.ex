defmodule YtSearch.Thumbnail do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}

  schema "thumbnails" do
    field(:mime_type, :string)
    field(:data, :binary)
    timestamps()
  end

  @spec fetch(String.t()) :: Thumbnail.t()
  def fetch(id) do
    query = from s in __MODULE__, where: s.id == ^id, select: s
    Repo.one(query)
  end

  def insert(id, mimetype, blob) do
    %__MODULE__{id: id, mime_type: mimetype, data: blob}
    |> Repo.insert!()
  end
end
