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
    field(:type, :integer)
  end

  def type(slot) do
    case slot.type do
      0 -> :video
      1 -> :livestream
    end
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
      max_ids: 150_000,

      # 20 minutes so that we can reuse search slots
      ttl: 20 * 60
    }
  end

  def changeset(%__MODULE__{} = slot, params) do
    slot
    |> cast(params, [:id, :youtube_id, :video_duration, :expires_at, :used_at, :keepalive, :type])
    |> validate_required([:youtube_id, :video_duration, :expires_at, :used_at])
  end

  def changeset(params) do
    %__MODULE__{}
    |> changeset(params)
  end

  @spec create(String.t(), Integer.t() | nil, Keyword.t()) :: Slot.t()
  def create(youtube_id, video_duration, opts \\ []) do
    keepalive = opts |> Keyword.get(:keepalive, false)

    SlotRepo.transaction(
      fn ->
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
              keepalive: keepalive,
              type:
                case Keyword.get(opts, :type) do
                  :video -> 0
                  :short -> 0
                  :livestream -> 1
                  nil -> 0
                end
            }
            |> SlotUtilities.put_simple_expiration(__MODULE__)
            |> SlotUtilities.put_used()

          Logger.info(
            "allocating slot #{new_id} to #{youtube_id} (type #{params[:type]}, duration #{params[:video_duration]})"
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
                type: params.type,
                keepalive: keepalive
              ]
            ]
          )
        else
          maybe_slot
          |> refresh(opts)
        end
      end,
      mode: :immediate
    )
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
      |> SlotUtilities.put_simple_expiration(__MODULE__)
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
      |> SlotUtilities.put_simple_expiration(__MODULE__)
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
