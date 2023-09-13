defmodule YtSearch.ChannelSlot do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo
  alias YtSearch.SlotUtilities
  alias YtSearch.TTL
  require Logger

  @type t :: %__MODULE__{}
  @primary_key {:id, :integer, autogenerate: false}

  # 20 times to retry
  def max_id_retries, do: 1
  # 2 hours
  def ttl, do: 2 * 60 * 60
  # this number must be synced with the world build
  def urls, do: 60_000

  schema "channel_slots" do
    field(:youtube_id, :string)
    timestamps()
  end

  @spec fetch(Integer.t()) :: Slot.t() | nil
  def fetch(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s
    Repo.one(query)
  end

  @spec fetch_by_youtube_id(String.t()) :: t() | nil
  def fetch_by_youtube_id(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    Repo.all(query)
    |> Enum.filter(fn channel_slot ->
      TTL.maybe?(channel_slot, __MODULE__) != nil
    end)
    |> Enum.at(0)
  end

  @spec from(String.t()) :: Slot.t()
  def from(youtube_id) do
    if String.length(youtube_id) == 0 do
      raise "invalid youtube id"
    end

    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    channel_slot =
      Repo.all(query)
      |> Enum.filter(fn channel_slot ->
        TTL.maybe?(channel_slot, __MODULE__) != nil
      end)
      |> Enum.at(0)

    if channel_slot == nil do
      {:ok, new_id} = find_available_id()

      %__MODULE__{youtube_id: youtube_id, id: new_id}
      |> Repo.insert!()
    else
      channel_slot
    end
  end

  @spec find_available_id() :: {:ok, Integer.t()} | {:error, :no_available_id}
  defp find_available_id() do
    SlotUtilities.find_available_slot_id(__MODULE__)
  end

  def as_youtube_url(slot) do
    case slot.youtube_id do
      "@" <> _rest ->
        raise "unsupported"

      youtube_id ->
        "https://www.youtube.com/channel/#{youtube_id}"
    end
  end

  def refresh(channel_slot_id) do
    query = from s in __MODULE__, where: s.id == ^channel_slot_id, select: s
    channel_slot = Repo.one(query)

    unless channel_slot == nil do
      Logger.info("refreshing channel id #{channel_slot.id}")

      channel_slot
      |> Ecto.Changeset.change(
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      )
      |> YtSearch.Repo.update!()
    end
  end
end
