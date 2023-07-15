defmodule YtSearch.Slot do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo
  alias YtSearch.TTL
  alias YtSearch.SlotUtilities

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}

  schema "slots_v2" do
    field(:youtube_id, :string)
    field(:video_duration, :integer)
    timestamps()

    timestamps(
      inserted_at: :inserted_at_v2,
      updated_at: false,
      type: :integer,
      autogenerate: {__MODULE__, :gen_inserted_v2, []}
    )
  end

  def gen_inserted_v2() do
    DateTime.to_unix(DateTime.utc_now())
  end

  @spec fetch_by_id(Integer.t()) :: Slot.t() | nil
  def fetch_by_id(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s

    Repo.one(query)
    |> TTL.maybe_video?(__MODULE__)
  end

  @spec create(String.t(), Integer.t() | nil) :: Slot.t()
  def create(youtube_id, video_duration) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    maybe_slot = Repo.one(query)

    if maybe_slot == nil do
      {:ok, new_id} = find_available_id()

      %__MODULE__{
        youtube_id: youtube_id,
        id: new_id,
        video_duration:
          case video_duration do
            nil -> default_ttl()
            duration -> duration |> trunc
          end
      }
      |> Repo.insert!()
    else
      if TTL.expired_video?(maybe_slot, __MODULE__) do
        # we want this youtube id created, but the slot for it is expired...
        # instead of deleting it or generating a new one, renew it
        # by setting inserted_at to current timestamp
        maybe_slot
        |> Ecto.Changeset.change(
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        )
        |> Ecto.Changeset.change(inserted_at_v2: DateTime.to_unix(DateTime.utc_now()))
        |> YtSearch.Repo.update!()
      else
        maybe_slot
      end
    end
  end

  def max_id_retries, do: 15
  # 10 minutes to 12 hours
  # defaults to 1h for slots without duration
  def min_ttl, do: 10 * 60
  def default_ttl, do: 60 * 60
  def max_ttl, do: 12 * 60 * 60
  # this number must be synced with the world build
  def urls, do: 100_000

  @spec find_available_id() :: {:ok, Integer.t()} | {:error, :no_available_id}
  defp find_available_id() do
    SlotUtilities.find_available_slot_id(__MODULE__)
  end

  defmodule Janitor do
    use GenServer
    require Logger

    alias YtSearch.Repo
    alias YtSearch.Subtitle

    import Ecto.Query

    def start_link(arg) do
      GenServer.start_link(__MODULE__, arg)
    end

    @impl true
    def init(_arg) do
      schedule_work()
      {:ok, %{}}
    end

    def handle_info(:work, state) do
      do_janitor()
      schedule_work()
      {:noreply, state}
    end

    def do_janitor() do
      Logger.debug("cleaning expired slots...")

      expired_slots =
        from(s in YtSearch.Slot, select: s)
        |> Repo.all()
        |> Enum.to_list()
        |> Enum.map(fn slot ->
          {slot, YtSearch.TTL.expired_video?(slot, YtSearch.Slot)}
        end)
        |> Enum.filter(fn {slot, expired?} -> expired? end)
        |> Enum.map(fn {expired_slot, true} ->
          Repo.delete(expired_slot)
        end)

      deleted_count = length(expired_slots)

      Logger.info("deleted #{deleted_count} slots")
    end

    defp schedule_work() do
      # every 10 minutes, with a jitter of -3..10m
      next_tick =
        case Mix.env() do
          :prod -> 10 * 60 * 1000 + Enum.random((-3 * 60 * 1000)..(10 * 60 * 1000))
          _ -> 10000
        end

      Process.send_after(self(), :work, next_tick)
    end
  end
end
