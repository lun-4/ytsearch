defmodule YtSearch.Thumbnail do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Data.ThumbnailRepo
  alias YtSearch.Data.ThumbnailRepo.JanitorReplica
  alias YtSearch.SlotUtilities
  import Ecto.Changeset
  require Logger

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}

  schema "thumbnails_v2" do
    field(:mime_type, :string)
    timestamps()
    field(:expires_at, :naive_datetime)
    field(:used_at, :naive_datetime)
    field(:keepalive, :boolean)
  end

  @spec fetch(String.t()) :: Thumbnail.t()
  def fetch(id) do
    query = from s in __MODULE__, where: s.id == ^id, select: s
    ThumbnailRepo.replica(id).one(query)
  end

  def blob(nil), do: nil

  def blob(%__MODULE__{} = thumb) do
    blob(thumb.id)
  end

  def blob(id) when is_bitstring(id) do
    case File.read(path_for(id)) do
      {:ok, data} -> data
      {:error, :enoent} -> nil
    end
  end

  def changeset(%__MODULE__{} = slot, params) do
    slot
    |> cast(params, [:id, :mime_type, :expires_at, :used_at, :keepalive])
    |> validate_required([:id, :mime_type, :expires_at, :used_at])
  end

  def slot_spec do
    %{
      # 24 hours
      ttl: 24 * 60 * 60
    }
  end

  def insert(id, mimetype, opts) do
    %__MODULE__{}
    |> changeset(
      %{
        id: id,
        mime_type: mimetype,
        keepalive: Keyword.get(opts, :keepalive, false)
      }
      |> SlotUtilities.put_simple_expiration(__MODULE__)
      |> SlotUtilities.put_used()
    )
    |> ThumbnailRepo.insert!()
  end

  def path_for(id) do
    "thumbnails/#{id}"
  end

  def insert(id, mimetype, blob, opts) do
    thumb = insert(id, mimetype, opts)
    File.write!(path_for(id), blob)
    thumb
  end

  defmodule Janitor do
    require Logger

    alias YtSearch.Data.ThumbnailRepo
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
        |> JanitorReplica.all()
        |> Enum.chunk_every(100)
        |> Enum.map(fn chunk ->
          ids = chunk |> Enum.map(fn t -> t.id end)

          {count, _} =
            from(t in Thumbnail, where: t.id in ^ids)
            |> ThumbnailRepo.delete_all()

          ids
          |> Enum.each(fn id ->
            File.rm(Thumbnail.path_for(id))
          end)

          # let other ops run for a while
          :timer.sleep(1000)
          count
        end)
        |> Enum.sum()

      Logger.info("deleted #{deleted_count} thumbnails")
      deleted_count
    end
  end
end
