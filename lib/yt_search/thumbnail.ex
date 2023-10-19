defmodule YtSearch.Thumbnail do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo
  alias YtSearch.SlotUtilities
  import Ecto.Changeset
  require Logger

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}

  schema "thumbnails" do
    field(:mime_type, :string)
    field(:data, :binary)
    timestamps()
    field(:expires_at, :naive_datetime)
    field(:used_at, :naive_datetime)
    field(:keepalive, :boolean)
  end

  @spec fetch(String.t()) :: Thumbnail.t()
  def fetch(id) do
    query = from s in __MODULE__, where: s.id == ^id, select: s
    Repo.one(query)
  end

  def changeset(%__MODULE__{} = slot, params) do
    slot
    |> cast(params, [:id, :mime_type, :data, :expires_at, :used_at, :keepalive])
    |> validate_required([:id, :mime_type, :data, :expires_at, :used_at])
  end

  def slot_spec do
    %{
      # 24 hours
      ttl: 24 * 60 * 60
    }
  end

  def insert(id, mimetype, blob, opts) do
    %__MODULE__{}
    |> changeset(
      %{
        id: id,
        mime_type: mimetype,
        data: blob,
        keepalive: Keyword.get(opts, :keepalive, false)
      }
      |> SlotUtilities.put_simple_expiration(__MODULE__)
      |> SlotUtilities.put_used()
    )
    |> Repo.insert!()
  end

  defmodule Janitor do
    require Logger

    alias YtSearch.Repo
    alias YtSearch.Thumbnail

    import Ecto.Query

    def tick() do
      Logger.info("cleaning thumbnails...")

      now = SlotUtilities.generate_unix_timestamp_integer()

      Repo.put_dynamic_repo(Repo.janitor_repo_id())

      deleted_count =
        from(s in Thumbnail,
          where: fragment("unixepoch(?)", s.expires_at) < ^now and not s.keepalive,
          limit: 5000
        )
        |> Repo.all()
        |> Enum.chunk_every(100)
        |> Enum.map(fn chunk ->
          chunk
          |> Enum.map(fn thumb ->
            Repo.delete(thumb)
            1
          end)
          |> then(fn results ->
            # let other ops run for a while
            :timer.sleep(1000)
            results
          end)
          |> Enum.sum()
        end)
        |> Enum.sum()

      Logger.info("deleted #{deleted_count} thumbnails")
      deleted_count
    end
  end

  def refresh(id) do
    query = from s in __MODULE__, where: s.id == ^id, select: s
    slot = Repo.one(query)

    unless slot == nil do
      Logger.info("refreshed thumbnail id #{id}")

      slot
      |> Ecto.Changeset.change(
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      )
      |> YtSearch.Repo.update!()
    end
  end
end
