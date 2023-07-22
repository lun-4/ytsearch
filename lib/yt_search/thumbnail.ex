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

  # 2 hours
  def ttl_seconds(), do: 2 * 60 * 60

  def insert(id, mimetype, blob) do
    %__MODULE__{id: id, mime_type: mimetype, data: blob}
    |> Repo.insert!()
  end

  defmodule Janitor do
    require Logger

    alias YtSearch.Repo
    alias YtSearch.Thumbnail

    import Ecto.Query

    def tick() do
      Logger.debug("cleaning thumbnails...")

      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-Thumbnail.ttl_seconds())

      deleted_count =
        from(s in Thumbnail,
          where:
            s.inserted_at <
              ^expiry_time,
          limit: 30
        )
        |> Repo.all()
        |> Enum.map(fn thumb ->
          Repo.delete(thumb)
          1
        end)
        |> Enum.sum()

      Logger.info("deleted #{deleted_count} thumbnails")
    end
  end
end
