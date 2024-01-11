defmodule YtSearch.Slot do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  require Logger
  alias YtSearch.Data.SlotRepo
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

    SlotRepo.replica(slot_id).one(query)
    |> SlotUtilities.strict_ttl()
  end

  @spec fetch_by_youtube_id(String.t()) :: Slot.t() | nil
  def fetch_by_youtube_id(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    SlotRepo.replica(youtube_id).one(query)
    |> SlotUtilities.strict_ttl()
  end

  def slot_spec() do
    %{
      # this number must be synced with the world build
      max_ids: 100_000
    }
  end

  @min_ttl 10 * 60
  @default_ttl 30 * 60
  @max_ttl 12 * 60 * 60

  defp expiration_for(duration, opts \\ []) do
    ttl =
      if opts |> Keyword.get(:entity_type) == :livestream do
        3 * 60 * 60
      else
        if duration != nil do
          max(@min_ttl, min((4 * duration) |> trunc, @max_ttl))
        else
          @default_ttl
        end
      end

    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(ttl)
    |> NaiveDateTime.truncate(:second)
  end

  def put_expiration(params) do
    params
    |> Map.put(:expires_at, expiration_for(params.video_duration))
  end

  def put_expiration(params, %__MODULE__{} = slot, opts) do
    params
    |> Map.put(:expires_at, expiration_for(slot.video_duration, opts))
  end

  def put_expiration(params, opts) do
    params
    |> Map.put(:expires_at, expiration_for(params.video_duration, opts))
  end

  def is_expired?(%__MODULE__{} = slot) do
    NaiveDateTime.compare(NaiveDateTime.utc_now(), slot.expires_at) == :gt
  end

  def changeset(%__MODULE__{} = slot, params) do
    slot
    |> cast(params, [:id, :youtube_id, :video_duration, :expires_at, :used_at, :keepalive])
    |> validate_required([:youtube_id, :video_duration, :expires_at, :used_at])
  end

  def changeset(params) do
    %__MODULE__{}
    |> changeset(params)
  end

  @spec create(String.t(), Integer.t() | nil, Keyword.t()) :: Slot.t()
  def create(youtube_id, video_duration, opts \\ []) do
    keepalive = opts |> Keyword.get(:keepalive, false)

    SlotRepo.transaction(fn ->
      query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s
      maybe_slot = SlotRepo.replica(youtube_id).one(query)

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
          |> put_expiration(opts)
          |> SlotUtilities.put_used()

        Logger.info(
          "allocating slot #{new_id} to #{youtube_id} (duration #{params[:video_duration]})"
        )

        params
        |> changeset
        |> SlotRepo.insert!(
          on_conflict: [
            set: [
              youtube_id: youtube_id,
              video_duration: video_duration,
              expires_at: params.expires_at,
              used_at: params.used_at,
              keepalive: keepalive
            ]
          ]
        )
      else
        maybe_slot
        |> refresh(opts)
      end
    end)
    |> then(fn {:ok, slot} -> slot end)
  end

  def refresh(slot, opts \\ [])

  def refresh(slot_id, opts) when is_number(slot_id) do
    Logger.info("refreshing video by id #{slot_id}")

    slot =
      from(s in __MODULE__, select: s, where: s.id == ^slot_id)
      |> SlotRepo.replica(slot_id).one()

    slot
    |> changeset(
      %{}
      |> put_expiration(slot, opts)
      |> SlotUtilities.put_used()
      |> SlotUtilities.put_opts(opts)
    )
    |> SlotRepo.update!()
  end

  def refresh(%__MODULE__{} = slot, opts) do
    Logger.info("refreshing video by slot #{slot.id}")

    slot
    |> change(
      %{}
      |> put_expiration(slot, opts)
      |> SlotUtilities.put_used()
      |> SlotUtilities.put_opts(opts)
    )
    |> SlotRepo.update!()
  end

  def used(%__MODULE__{} = slot) do
    Logger.info("used video id #{slot.id}")

    slot
    |> change(%{} |> SlotUtilities.put_used())
    |> SlotRepo.update!()
  end

  def youtube_url(slot) do
    "https://youtube.com/watch?v=#{slot.youtube_id}"
  end

  def urls, do: 0
end
