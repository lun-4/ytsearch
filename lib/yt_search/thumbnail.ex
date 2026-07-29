defmodule YtSearch.Thumbnail do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Data.ThumbnailRepo
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

  # batched equivalent of fetch/1: returns a map of id => Thumbnail for the
  # ids that exist. missing ids are simply absent (Map.get yields nil),
  # matching how the single fetch returns nil for a missing row.
  @spec batch_fetch([String.t()]) :: %{String.t() => t()}
  def batch_fetch([]), do: %{}

  def batch_fetch(ids) do
    from(s in __MODULE__, where: s.id in ^ids)
    |> ThumbnailRepo.replica().all()
    |> Map.new(&{&1.id, &1})
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

  def stat(%__MODULE__{} = thumb) do
    case File.stat(path_for(thumb.id)) do
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

  # INVARIANT: the image file at path_for(id) must be fully written BEFORE the
  # row is inserted. Atlas.internal_assemble's mutex-free fast path serves the
  # file directly whenever a row exists with no in-flight download task, so a
  # row that becomes visible before its file leads to half-written atlases.
  # insert/3 callers must write the file first; insert/4 does it for you.
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
    # file before row — see INVARIANT above
    File.write!(path_for(id), blob)
    insert(id, mimetype, opts)
  end

  defmodule Janitor do
    alias YtSearch.Data.ThumbnailRepo
    alias YtSearch.Thumbnail

    def tick() do
      YtSearch.Janitor.sweep(
        name: "thumbnails",
        schema: Thumbnail,
        repo: ThumbnailRepo,
        replica: ThumbnailRepo.JanitorReplica,
        keys: [:id],
        expiry_column: :expires_at,
        ttl: 0,
        extra_where: dynamic([s], not s.keepalive),
        select_limit: 14000,
        chunk_size: 500,
        sleep_ms: 750,
        file_path: fn row -> Thumbnail.path_for(row.id) end
      )
    end
  end
end
