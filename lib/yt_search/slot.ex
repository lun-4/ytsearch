defmodule YtSearch.Slot do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  require Logger
  alias YtSearch.Repo
  alias YtSearch.TTL
  alias YtSearch.SlotUtilities

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}

  schema "slots_v3" do
    field(:youtube_id, :string)
    field(:video_duration, :integer)
    timestamps(autogenerate: {SlotUtilities, :generate_unix_timestamp, []})
    field(:expires_at, :naive_datetime)
    field(:used_at, :naive_datetime)
    field(:keepalive, :boolean)
  end

  @spec fetch_by_id(Integer.t()) :: Slot.t() | nil
  def fetch_by_id(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s

    Repo.one(query)
    |> SlotUtilities.strict_ttl()
  end

  @spec fetch_by_youtube_id(String.t()) :: Slot.t() | nil
  def fetch_by_youtube_id(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    Repo.one(query)
    |> SlotUtilities.strict_ttl()
  end

  def slot_spec() do
    %{
      max_id_retries: 2,
      # this number must be synced with the world build
      max_urls: 100_000
    }
  end

  @min_ttl 10 * 60
  @default_ttl 30 * 60
  @max_ttl 12 * 60 * 60

  defp expiration_for(duration) do
    ttl =
      if duration != nil do
        max(@min_ttl, min((4 * duration) |> trunc, @max_ttl))
      else
        @default_ttl
      end

    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(ttl)
    |> NaiveDateTime.truncate(:second)
  end

  def put_expiration(params) do
    params
    |> Map.put(:expires_at, expiration_for(params.video_duration))
  end

  def put_expiration(params, %__MODULE__{} = slot) do
    params
    |> Map.put(:expires_at, expiration_for(slot.video_duration))
  end

  defp put_used(params) do
    params
    |> Map.put(
      :used_at,
      NaiveDateTime.utc_now()
      |> NaiveDateTime.truncate(:second)
    )
  end

  def is_expired?(%__MODULE__{} = slot) do
    NaiveDateTime.compare(NaiveDateTime.utc_now(), slot.expires_at) == :gt
  end

  defp changeset(%__MODULE__{} = slot, params) do
    slot
    |> cast(params, [:id, :youtube_id, :video_duration, :expires_at, :used_at, :keepalive])
    |> validate_required([:youtube_id, :video_duration, :expires_at, :used_at])
  end

  defp changeset(params) do
    %__MODULE__{}
    |> changeset(params)
  end

  @spec create(String.t(), Integer.t() | nil, boolean()) :: Slot.t()
  def create(youtube_id, video_duration, keepalive \\ false) do
    Repo.transaction(fn ->
      query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s
      maybe_slot = Repo.one(query)

      if maybe_slot == nil do
        {:ok, new_id} = SlotUtilities.generate_id_v3(__MODULE__)

        params =
          %{
            id: new_id,
            youtube_id: youtube_id,
            video_duration:
              case video_duration do
                nil -> 10 * 60
                duration -> duration |> trunc
              end,
            keepalive: keepalive
          }
          |> put_expiration()
          |> put_used()

        params
        |> changeset
        |> Repo.insert!(
          on_conflict: [
            set: [
              youtube_id: youtube_id,
              video_duration: video_duration,
              expires_at: params.expires_at,
              used_at: params.used_at
            ]
          ]
        )
      else
        maybe_slot
        |> refresh()
      end
    end)
    |> then(fn {:ok, slot} -> slot end)
  end

  def refresh(slot_id) when is_number(slot_id) do
    Logger.info("refreshing video id #{slot_id}")

    slot =
      from(s in __MODULE__, select: s, where: s.id == ^slot_id)
      |> Repo.one()

    slot
    |> changeset(%{} |> put_expiration(slot))
    |> Repo.update!()
  end

  def refresh(%__MODULE__{} = slot) do
    Logger.info("refreshing video id #{slot.id}")

    slot
    |> put_expiration()
    |> change
    |> Repo.update!()
  end

  def used(%__MODULE__{} = slot) do
    Logger.info("used video id #{slot.id}")

    slot
    |> put_used()
    |> changeset
    |> Repo.update!()
  end

  @spec find_available_id() :: {:ok, Integer.t()} | {:error, :no_available_id}
  defp find_available_id() do
    SlotUtilities.find_available_slot_id(__MODULE__)
  end

  defmodule Janitor do
    require Logger

    alias YtSearch.Repo

    import Ecto.Query

    def tick() do
      Logger.debug("cleaning expired slots...")

      expired_slots =
        from(s in YtSearch.Slot, select: s)
        |> Repo.all()
        |> Enum.to_list()
        |> Enum.map(fn slot ->
          {slot, YtSearch.TTL.expired?(slot)}
        end)
        |> Enum.filter(fn {_slot, expired?} -> expired? end)
        |> Enum.map(fn {expired_slot, true} ->
          Repo.delete(expired_slot)
        end)

      deleted_count = length(expired_slots)

      Logger.info("deleted #{deleted_count} slots")
    end
  end

  def youtube_url(slot) do
    "https://youtube.com/watch?v=#{slot.youtube_id}"
  end
end
