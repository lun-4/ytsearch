defmodule YtSearch.ChannelSlot do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo
  alias YtSearch.TTL
  alias YtSearch.SlotUtilities

  @type t :: %__MODULE__{}
  @primary_key {:id, :integer, autogenerate: false}

  # 20 times to retry
  def max_id_retries, do: 20
  # 12 hours
  def ttl, do: 12 * 60 * 60
  # this number must be synced with the world build
  def urls, do: 100_000

  schema "channel_slots" do
    field(:youtube_id, :string)
    timestamps()
  end

  @spec fetch(Integer.t()) :: Slot.t() | nil
  def fetch(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s
    Repo.one(query)
  end

  @spec from(String.t()) :: Slot.t()
  def from(youtube_id) do
    if String.length(youtube_id) == 0 do
      raise "invalid youtube id"
    end

    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    case Repo.one(query) do
      nil ->
        {:ok, new_id} = find_available_id()

        %__MODULE__{youtube_id: youtube_id, id: new_id}
        |> Repo.insert!()

      slot ->
        slot
    end
  end

  @spec find_available_id() :: {:ok, Integer.t()} | {:error, :no_available_id}
  defp find_available_id() do
    SlotUtilities.find_available_slot_id(__MODULE__)
  end

  def as_youtube_url(slot) do
    case slot.youtube_id do
      "@" <> _rest ->
        "https://www.youtube.com/#{slot.youtube_id}/videos"

      youtube_id ->
        "https://www.youtube.com/channel/#{youtube_id}/videos"
    end
  end
end
