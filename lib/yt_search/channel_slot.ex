defmodule YtSearch.ChannelSlot do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo
  alias YtSearch.SlotUtilities
  import Ecto.Changeset
  require Logger

  @type t :: %__MODULE__{}
  @primary_key {:id, :integer, autogenerate: false}

  schema "channel_slots_v3" do
    field(:youtube_id, :string)
    timestamps(autogenerate: {SlotUtilities, :generate_unix_timestamp, []})
    field(:expires_at, :naive_datetime)
    field(:used_at, :naive_datetime)
    field(:keepalive, :boolean)
  end

  @spec fetch(Integer.t()) :: Slot.t() | nil
  def fetch(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s

    Repo.replica(slot_id).one(query)
    |> SlotUtilities.strict_ttl()
  end

  @spec fetch_by_youtube_id(String.t()) :: t() | nil
  def fetch_by_youtube_id(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    Repo.replica(youtube_id).one(query)
    |> SlotUtilities.strict_ttl()
  end

  def changeset(%__MODULE__{} = slot, params) do
    slot
    |> cast(params, [:id, :youtube_id, :expires_at, :used_at, :keepalive])
    |> validate_required([:youtube_id, :expires_at, :used_at])
  end

  @spec create(String.t(), Keyword.t()) :: t()
  def create(youtube_id, opts \\ []) do
    keepalive = Keyword.get(opts, :keepalive, false)

    if String.length(youtube_id) == 0 do
      raise "invalid youtube id"
    end

    Repo.transaction(fn ->
      query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s
      channel_slot = Repo.replica(youtube_id).one(query)

      if channel_slot == nil do
        {:ok, new_id} = SlotUtilities.generate_id_v3(__MODULE__)

        params =
          %{
            id: new_id,
            youtube_id: youtube_id,
            keepalive: keepalive
          }
          |> SlotUtilities.put_simple_expiration(__MODULE__)
          |> SlotUtilities.put_used()

        %__MODULE__{}
        |> changeset(params)
        |> Repo.insert!(
          on_conflict: [
            set: [
              youtube_id: youtube_id,
              expires_at: params.expires_at,
              used_at: params.used_at,
              keepalive: keepalive
            ]
          ]
        )
      else
        channel_slot
        |> SlotUtilities.refresh_expiration(opts)
      end
    end)
    |> then(fn {:ok, slot} -> slot end)
  end

  def slot_spec() do
    %{
      # this number must be synced with the world build
      max_ids: 60_000,
      # 2 hours
      ttl: 2 * 60 * 60
    }
  end

  def urls, do: 0
end
