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
    Repo.replica().one(query)
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

      deleted_count =
        from(s in Thumbnail,
          where: fragment("unixepoch(?)", s.expires_at) < ^now and not s.keepalive,
          limit: 14000
        )
        |> Repo.replica().all()
        |> Enum.chunk_every(25)
        |> Enum.map(fn chunk ->
          ids = chunk |> Enum.map(fn t -> t.id end)

          {count, _} =
            from(t in Thumbnail, where: t.id in ^ids)
            |> Repo.delete_all()

          # let other ops run for a while
          :timer.sleep(1000)
          count
        end)
        |> Enum.sum()

      Logger.info("deleted #{deleted_count} thumbnails")
      deleted_count
    end
  end

  def refresh(id) do
    query = from s in __MODULE__, where: s.id == ^id, select: s
    slot = Repo.replica().one(query)

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
